defmodule Quincunx.Session.Server do
  @moduledoc """
  Provide a GenServer.
  """
  use GenServer

  alias Quincunx.Editor.{Segment, History.Resolver, History.Operation}
  alias Quincunx.Session.Storage
  alias Quincunx.Renderer.{Blackboard, Planner, Dispatcher}
  alias Quincunx.Compiler.{GraphBuilder, RecipeBundle}

  defmodule State do
    @type t :: %__MODULE__{
            session_id: term(),
            segments: %{Segment.id() => Segment.t()},
            static_bundles_cache: %{Segment.id() => [RecipeBundle.t()]},
            blackboard: Blackboard.t(),
            storage: Storage.t() | nil
          }
    defstruct [
      :session_id,
      :storage,
      segments: %{},
      static_bundles_cache: %{},
      blackboard: nil
    ]
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    storage = if Keyword.get(opts, :enable_cache, true), do: Storage.new(), else: nil

    {:ok,
     %State{
       session_id: session_id,
       storage: storage,
       blackboard: Blackboard.new(session_id)
     }}
  end

  @impl true
  def handle_cast({:apply_operation, seg_id, op}, %State{} = state) do
    segment = Map.fetch!(state.segments, seg_id)
    updated_segment = Segment.apply_operation(segment, op)

    state = put_in(state.segments[seg_id], updated_segment)

    state =
      if Operation.topology?(op) do
        %{state | static_bundles_cache: Map.delete(state.static_bundles_cache, seg_id)}
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_call({:dispatch, dispatch_opts}, _from, %State{} = state) do
    compiled =
      Enum.map(state.segments, fn {seg_id, segment} ->
        compile_segment(seg_id, segment, state.static_bundles_cache)
      end)

    new_cache = Map.new(compiled, fn {id, _, static} -> {id, static} end)
    state = %{state | static_bundles_cache: new_cache}

    executable_pairs = Enum.map(compiled, fn {id, bundles, _} -> {id, bundles} end)

    # Inject session-owned storage into plugin scope using its canonical key
    full_opts =
      dispatch_opts
      |> Keyword.put(OrchidPlugin.Cache.scope_name(), state.storage)

    with {:ok, plan} <- Planner.build(executable_pairs),
         {:ok, new_board} <- Dispatcher.dispatch(plan, state.blackboard, full_opts) do
      {:reply, :ok, %{state | blackboard: new_board}}
    else
      {:error, _} = err -> {:reply, err, state}
    end
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
