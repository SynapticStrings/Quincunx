defmodule Quincunx.Renderer.Dispatcher do
  @moduledoc """
  Orchestrates barrier-synchronized execution of stages.

  Sole responsibility: fan-out tasks per stage, collect results,
  enforce barrier before next stage.  All configuration is carried
  by `Renderer.Context`.
  """

  alias Quincunx.Renderer.{Planner, Worker, Blackboard, Context}

  @spec dispatch(Planner.Plan.t(), Blackboard.t(), keyword()) ::
          {:ok, Blackboard.t()} | {:error, term()}
  def dispatch(%Planner.Plan{} = plan, %Blackboard{} = board, opts \\ []) do
    ctx = Context.new(opts)

    Enum.reduce_while(plan.stages, {:ok, board}, fn stage, {:ok, current_board} ->
      case run_stage(stage, current_board, ctx) do
        {:ok, updated_board} -> {:cont, {:ok, updated_board}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_stage(stage, blackboard, %Context{} = ctx) do
    stage.tasks
    |> Task.async_stream(
      fn {seg_id, bundle} -> Worker.run(seg_id, bundle, blackboard, ctx) end,
      max_concurrency: ctx.concurrency,
      timeout: ctx.timeout,
      ordered: false
    )
    |> Enum.reduce_while({:ok, blackboard}, fn
      {:ok, {:ok, seg_id, outputs}}, {:ok, acc_board} ->
        {:cont, {:ok, merge_results(acc_board, seg_id, outputs)}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:worker_crashed, reason}}}
    end)
  end

  defp merge_results(%Blackboard{} = board, seg_id, outputs) do
    entries =
      outputs
      |> Enum.map(fn
        %Orchid.Param{} = p -> {{seg_id, p.name}, Orchid.Param.get_payload(p)}
        {port_name, p} -> {{seg_id, port_name}, Orchid.Param.get_payload(p)}
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Blackboard.put(board, entries)
  end
end
