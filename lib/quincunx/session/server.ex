defmodule Quincunx.Session.Server do
  @moduledoc """
  Provide a GenServer.
  """
  use GenServer

  require Logger

  alias Quincunx.Session.{Storage, Context}
  alias Quincunx.Session
  alias Quincunx.Editor.{Segment, History.Resolver}
  alias Quincunx.Renderer.{Planner, Dispatcher}
  alias Quincunx.Compiler.{GraphBuilder, RecipeBundle}

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: Session.server(session_id))
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    storage = if Keyword.get(opts, :enable_cache, true), do: Storage.new(), else: nil

    {:ok, Context.new(session_id, storage)}
  end

  @impl true
  def handle_cast({:add_segment, %Segment{} = segment}, %Context{} = state) do
    {:noreply, Context.add_segment(state, segment)}
  end

  @impl true
  def handle_cast({:remove_segment, seg_id}, %Context{} = state) do
    new_state = %{state |
      segments: Map.delete(state.segments, seg_id),
      static_bundles_cache: Map.delete(state.static_bundles_cache, seg_id)
    }
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:apply_operation, seg_id, op}, %Context{} = state) do
    case Context.operate(state, seg_id, op) do
      %Context{} = new_state -> {:noreply, new_state}
      {:seg_not_exist, ^seg_id} -> {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:dispatch, dispatch_opts}, %Context{} = state) do
    case compile_and_plan(state) do
      {new_state, {:ok, plan}} ->
        if state.render_tasks do
          Task.Supervisor.terminate_child(
            Session.task_sup(state.session_id),
            new_state.render_tasks.pid
          )
        end

        task =
          Task.Supervisor.async_nolink(
            Session.task_sup(state.session_id),
            fn ->
              Dispatcher.dispatch(plan, new_state.blackboard, dispatch_opts)
            end
          )

        {:noreply, %{new_state | render_tasks: task}}

      {_legacy_state, {:error, _}} = _err ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, {:ok, new_board}}, %Context{render_tasks: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    {:noreply, %{state | blackboard: new_board, render_tasks: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %Context{render_tasks: %{ref: ref}} = state) do
    if reason != :killed do
      require Logger
      Logger.error("Engine crashed!\n\nReason: #{inspect(reason)}")
    end

    {:noreply, %{state | render_tasks: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Cought unknown message:\n\n#{inspect(msg)}")

    {:noreply, state}
  end

  defp compile_and_plan(%Context{} = state) do
    compiled =
      Enum.map(state.segments, fn {seg_id, segment} ->
        compile_segment(seg_id, segment, state.static_bundles_cache)
      end)

    new_cache = Map.new(compiled, fn {id, _, static} -> {id, static} end)
    state = %{state | static_bundles_cache: new_cache}

    executable_pairs = Enum.map(compiled, fn {id, bundles, _} -> {id, bundles} end)

    {state, Planner.build(executable_pairs)}
  end

  defp compile_segment(seg_id, segment, cache) do
    resolved = Resolver.resolve(segment.history, segment.graph)

    static_recipes =
      case Map.fetch(cache, seg_id) do
        {:ok, cached_static} ->
          cached_static

        :error ->
          {:ok, compiled} = GraphBuilder.compile_graph(resolved.graph, segment.cluster)

          compiled
      end

    executable_bundles = RecipeBundle.bind_interventions(static_recipes, resolved.interventions)

    {seg_id, executable_bundles, static_recipes}
  end
end
