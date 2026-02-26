defmodule Quincunx.Session.Renderer.Task do
  alias Quincunx.Session.Segment

  @type blackboard :: %{
          optional({Segment.id(), Lily.Graph.Portkey.t()}) => any()
        }

  @spec run([Segment.t()], map(), keyword()) :: {:ok, blackboard()} | {:error, any()}
  def run(segments, init_context \\ %{}, opts \\ []) do
    with {:ok, compiled_segments} <- Segment.compile_batch(segments) do
      compiled_segments
      |> align_stages()
      |> Enum.reduce_while({:ok, init_context}, fn stage_batch, {:ok, board} ->
          case execute_stage(stage_batch, board, opts) do
            {:ok, new_board} -> {:cont, {:ok, new_board}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp align_stages(compiled_segments) do
    compiled_segments
    |> Enum.map(fn {id, recipes} -> Enum.map(recipes, &{id, &1}) end)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  # --- Stage Execution Core ---

  defp execute_stage(batch, blackboard, opts) do
    concurrency = opts[:concurrency] || System.schedulers_online() * 2
    timeout = opts[:timeout] || 30_000

    # 这里的 Task.async_stream 是并发的核心
    # 它并行处理 batch 中的每一个 Segment 的当前 Stage Recipe
    results =
      Task.async_stream(
        batch,
        fn {seg_id, recipe} ->
          run_recipe(seg_id, recipe, blackboard)
        end, max_concurrency: concurrency, timeout: timeout, ordered: false)

    # 收集结果并合并回黑板 (Reduce)
    Enum.reduce_while(results, {:ok, blackboard}, fn
      {:ok, {:ok, seg_id, outputs}}, {:ok, acc_board} ->
        # 将 outputs 合并入黑板
        updated_board = merge_outputs(acc_board, seg_id, outputs)
        {:cont, {:ok, updated_board}}

      {:ok, {:error, reason}}, _ ->
        {:halt, {:error, reason}}

      {:exit, reason}, _ ->
        {:halt, {:error, {:task_exit, reason}}}
    end)
  end

  defp run_recipe(seg_id, recipe, blackboard) do
    # 1. 准备输入：从黑板中通过 requires 声明抓取数据
    # Recipe 里的 bound inputs (interventions) 已经在 compile 阶段绑定在 recipe 内部了
    # 这里我们只关心 upstream 传下来的 dynamic dependencies
    inputs = resolve_dependencies(blackboard, seg_id, recipe.requires)

    # 2. 调用 Orchid 执行器 (Side-effect boundary)
    # Orchid.run 应该返回 {:ok, outputs} 其中 outputs 是 %{port_key => value}
    case Orchid.run(recipe, inputs) do
      {:ok, outputs} -> {:ok, seg_id, outputs}
      err -> err
    end
  end

  # --- Blackboard Helpers ---

  # 根据 requires 列表，从黑板提取数据
  # Blackboard Key: {seg_id, port_key}
  defp resolve_dependencies(blackboard, seg_id, requires) do
    Enum.reduce(requires, %{}, fn port_key, acc ->
      key = {seg_id, port_key}

      case Map.fetch(blackboard, key) do
        {:ok, val} ->
          Map.put(acc, port_key, val)

        :error ->
          # 如果缺少依赖，这通常是编译器的 bug 或拓扑错误，但在运行时我们先忽略或报错
          # 这里为了健壮性，暂且允许空，Orchid 可能会在运行时检查
          acc
      end
    end)
  end

  # 将输出写回黑板
  defp merge_outputs(blackboard, seg_id, outputs) do
    # 将 Orchid key 改回 portkey
    Enum.reduce(outputs, blackboard, fn {port_key, value}, acc ->
      Map.put(acc, {seg_id, port_key}, value)
    end)
  end
end
