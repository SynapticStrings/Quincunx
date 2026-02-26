defmodule Quincunx.Session.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Lily.History.Operation
  alias Lily.{Graph, History, Compiler, Graph.Cluster}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          graph_with_cluster: {Graph.t(), Cluster.t()},
          compiled_recipes: nil | Orchid.Recipe.t(),
          history: History.t(),
          snapshots: %{optional(atom()) => any()},
          extra: map()
        }

  defstruct [
    :id,
    graph_with_cluster: {%Graph{}, %Cluster{}},
    compiled_recipes: nil,
    history: %History{},
    snapshots: %{},
    extra: %{}
  ]

  @spec new(id(), Graph.t()) :: t()
  @spec new(id(), Graph.t(), Cluster.t()) :: t()
  def new(id, graph_with_cluster, cluster_declara \\ %Cluster{}) do
    %__MODULE__{
      id: id,
      graph_with_cluster: {graph_with_cluster, cluster_declara},
      history: History.new()
    }
  end

  @spec apply_operation(t(), Operation.t()) :: t()
  def apply_operation(%__MODULE__{} = segment, operation) do
    %{segment | history: History.push(segment.history, operation)}
  end

  @spec undo(t()) :: t()
  def undo(%__MODULE__{} = segment) do
    %{segment | history: History.undo(segment.history)}
  end

  @spec redo(t()) :: t()
  def redo(%__MODULE__{} = segment) do
    %{segment | history: History.redo(segment.history)}
  end

  def compile_to_recipes(%__MODULE__{} = segment) do
    case compile_to_recipes([segment]) do
      {:ok, [compiled_seg]} -> {:ok, compiled_seg.compiled_recipes}
      {:error, _} = err -> err
    end
  end

  def compile_to_recipes(segments) when is_list(segments) do
    # 1. Resolve History -> {FinalGraph, Cluster, Interventions}
    # 我们先解析历史，拿到最终的图结构，这是分组的依据
    resolved_items =
      Enum.map(segments, fn seg ->
        {base_graph, cluster} = seg.graph_with_cluster
        {final_graph, interventions} = History.resolve(base_graph, seg.history)

        %{
          segment: seg,
          # Key 用于分组：只有图结构(final_graph)和分簇配置(cluster)都完全一致，才能复用配方
          group_key: {final_graph, cluster},
          interventions: interventions,
        }
      end)

    # 2. Group By Topology
    grouped = Enum.group_by(resolved_items, & &1.group_key)

    # 3. Compile & Bind
    # 使用 reduce_while 确保一旦出错（如有环）立即停止
    Enum.reduce_while(grouped, {:ok, []}, fn {{graph, cluster}, items}, {:ok, acc} ->
      # --- 关键点：每组只调用一次 compile ---
      case Compiler.compile(graph, cluster) do
        {:ok, static_recipes} ->
          # static_recipes 是 [Stage1_Recipe, Stage2_Recipe] (未绑定数据的模版)

          # 为组内每个 Segment 绑定其独有的 interventions
          compiled_group =
            Enum.map(items, fn item ->
              # bind_interventions 负责将 interventions 注入到 recipe 的 initial_params 或 overrides 中
              bound_recipes =
                static_recipes
                |> List.wrap()
                |> Compiler.bind_interventions(item.interventions)

              # 返回更新后的 Segment 结构
              %{item.segment | compiled_recipes: bound_recipes}
            end)

          {:cont, {:ok, acc ++ compiled_group}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
