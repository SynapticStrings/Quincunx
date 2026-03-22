defmodule Quincunx.Renderer.Dispatcher do
  @moduledoc """
  Orchestrates the barrier-synchronized execution of stages.
  """
  alias Quincunx.Renderer.{Planner, Worker, Blackboard}

  @doc """
  Runs the execution plan synchronously, applying barrier locks between stages.
  """
  def dispatch(%Planner.Plan{} = plan, %Blackboard{} = initial_board, opts \\ []) do
    storage_ctx = Keyword.get(opts, :storage)
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, :infinity)

    orchid_baggage = Keyword.get(opts, :orchid_baggage, [])

    Enum.reduce_while(plan.stages, {:ok, initial_board}, fn stage, {:ok, current_board} ->
      case run_stage(
             stage,
             current_board,
             concurrency,
             timeout,
             %{storage_ctx: storage_ctx},
             orchid_baggage,
             []
           ) do
        {:ok, updated_board} ->
          {:cont, {:ok, updated_board}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp run_stage(
         stage,
         blackboard,
         concurrency,
         timeout,
         features,
         orchid_baggage,
         orchid_opts
       ) do
    stream =
      Task.async_stream(
        stage.tasks,
        fn {seg_id, bundle} ->
          Worker.run(seg_id, bundle, blackboard, features, orchid_baggage, orchid_opts)
        end,
        max_concurrency: concurrency,
        timeout: timeout,
        ordered: false
      )

    Enum.reduce_while(stream, {:ok, blackboard}, fn
      {:ok, {:ok, seg_id, outputs}}, {:ok, acc_board} ->
        {:cont, {:ok, merge_results(acc_board, seg_id, outputs)}}

      {:ok, {:error, reason}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:worker_crashed, reason}}}
    end)
  end

  defp merge_results(%Blackboard{} = board, seg_id, outputs) do
    new_memory_entries =
      outputs
      |> Enum.map(fn
        %Orchid.Param{} = param -> {{seg_id, param.name}, Orchid.Param.get_payload(param)}
        {port_name, param} -> {{seg_id, port_name}, Orchid.Param.get_payload(param)}
      end)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.into(%{})

    Blackboard.put(board, new_memory_entries)
  end
end
