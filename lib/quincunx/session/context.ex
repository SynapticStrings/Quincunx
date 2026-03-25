defmodule Quincunx.Session.Context do
  @moduledoc """
  A container for representing `Quincunx.Session.Server` state.
  """

  alias Quincunx.Session.Storage
  alias Quincunx.Editor.{Segment, History}
  alias Quincunx.Renderer.{Blackboard, Planner}
  alias Quincunx.Compiler.{RecipeBundle, GraphBuilder}

  @type static_bundles_cache :: %{Segment.id() => [RecipeBundle.t()]}

  @type t :: %__MODULE__{
          session_id: Quincunx.Session.id(),
          segments: %{Segment.id() => Segment.t()},
          static_bundles_cache: %{Segment.id() => [RecipeBundle.t()]},
          blackboard: Blackboard.t(),
          storage: Storage.t() | nil,
          render_tasks: Task.t() | nil
        }
  defstruct [
    :session_id,
    :storage,
    segments: %{},
    static_bundles_cache: %{},
    blackboard: nil,
    render_tasks: nil
  ]

  @spec new(Quincunx.Session.id(), Storage.t() | nil) :: t()
  def new(session_id, storage) do
    %__MODULE__{
      session_id: session_id,
      storage: storage,
      blackboard: Blackboard.new(session_id)
    }
  end

  @spec add_segment(t(), Segment.t()) :: {:already_exist, Segment.id()} | {:ok, t()}
  def add_segment(%__MODULE__{} = ctx, %Segment{id: seg_id} = new_segment) do
    if Map.has_key?(ctx.segments, seg_id) do
      {:already_exist, seg_id}
    else
      {:ok, put_in(ctx.segments[seg_id], new_segment)}
    end
  end

  @spec remove_segment(t(), Segment.id()) :: t()
  def remove_segment(%__MODULE__{} = ctx, seg_id) do
    %{
      ctx
      | segments: Map.delete(ctx.segments, seg_id),
        static_bundles_cache: Map.delete(ctx.static_bundles_cache, seg_id)
    }
  end

  # push_segment

  # pop_segment

  @spec operate(t(), Segment.id(), History.Operation.t()) :: {:seg_not_exist, Segment.id()} | t()
  def operate(%__MODULE__{} = ctx, seg_id, op) do
    case Map.fetch(ctx.segments, seg_id) do
      {:ok, %Segment{} = seg} ->
        new_seg =
          case op do
            [_ | _] -> Enum.reduce(op, seg, &Segment.apply_operation(&2, &1))
            _ -> Segment.apply_operation(seg, op)
          end

        ctx.segments[seg_id]
        |> put_in(new_seg)
        |> maybe_clear_bundles_cache(seg_id, op)

      :error ->
        {:seg_not_exist, seg_id}
    end
  end

  @spec undo(t(), Segment.id()) :: {:seg_not_exist, Segment.id()} | t()
  def undo(%__MODULE__{} = ctx, seg_id) do
    case Map.fetch(ctx.segments, seg_id) do
      {:ok, %Segment{} = seg} ->
        {new_seg, op} = Segment.undo(seg)

        ctx.segments[seg_id]
        |> put_in(new_seg)
        |> maybe_clear_bundles_cache(seg_id, op)

      :error ->
        {:seg_not_exist, seg_id}
    end
  end

  @spec redo(t(), Segment.id()) :: {:seg_not_exist, Segment.id()} | t()
  def redo(%__MODULE__{} = ctx, seg_id) do
    case Map.fetch(ctx.segments, seg_id) do
      {:ok, %Segment{} = seg} ->
        {new_seg, op} = Segment.redo(seg)

        ctx.segments[seg_id]
        |> put_in(new_seg)
        |> maybe_clear_bundles_cache(seg_id, op)

      :error ->
        {:seg_not_exist, seg_id}
    end
  end

  @spec dispatch_to_plans(t()) :: {t(), Planner.Plan.t() | {:error, term()}}
  def dispatch_to_plans(%__MODULE__{} = ctx) do
    # {seg_id, derive, cached_static_or_compiled, recipe_bundle}
    compiled_results =
      Enum.map(ctx.segments, fn seg -> compile_segment(seg, ctx.static_bundles_cache) end)

    case Enum.find(compiled_results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        {ctx, error}

      _ ->
        # Build Planner from recipe bundle always return `{:ok, plan}`
        {:ok, plan} =
          compiled_results
          |> Enum.map(fn {id, _, _, bundle} -> {id, bundle} end)
          |> Planner.build()

        new_ctx = %{
          ctx
          | static_bundles_cache:
              Map.new(compiled_results, fn {id, _, static, _} -> {id, static} end)
        }

        {new_ctx, plan}
    end
  end

  # def execute_plans(%__MODULE__{} = _ctx, _plan) do
  #   # ...
  # end

  # Clear history and merge compiled graph and interventions into segments.
  # def create_snapshot(%__MODULE__{} = _ctx) do
  # end

  @spec compile_segment({Segment.id(), Segment.t()}, static_bundles_cache()) ::
          {:error, :cycle_detected}
          | {Segment.id(), derive :: :cache | :compile,
             cached_static_or_compiled_recipe :: [RecipeBundle.t()],
             recipe_bundle :: [RecipeBundle.t()]}
  def compile_segment({seg_id, %Segment{} = seg}, cache) do
    %{graph: effective_graph, interventions: interventions} =
      History.Resolver.resolve(seg.history, seg.graph)

    with {:cache, :error} <- {:cache, Map.fetch(cache, seg_id)},
         {:compile, {:error, _} = err} <-
           {:compile, GraphBuilder.compile_graph(effective_graph, seg.cluster)} do
      err
    else
      {derive, {:ok, cached_static_or_compiled}} ->
        recipe_bundle = RecipeBundle.bind_interventions(cached_static_or_compiled, interventions)

        {seg_id, derive, cached_static_or_compiled, recipe_bundle}
    end
  end

  defp maybe_clear_bundles_cache(%__MODULE__{} = ctx, seg_id, op) do
    if History.Operation.topology?(op) do
      %{ctx | static_bundles_cache: Map.delete(ctx.static_bundles_cache, seg_id)}
    else
      ctx
    end
  end
end
