defmodule Quincunx.Editor.SegmentManager do
  @moduledoc """
  Owns the Segment collection, grouping, inter-segment dependencies, and dirty tracking.

  Responsibilities:
  - Segment CRUD with group affiliation
  - Inter-segment dependency DAG (via LiteGraph)
  - Dirty propagation: marking a segment dirty transitively marks all dependents
  - Dispatch-order queries: topological ordering, group-aware batching
  """

  alias Quincunx.Editor.Segment
  # alias Quincunx.Editor.History
  alias Quincunx.Topology.LiteGraph
  alias Quincunx.Editor.{SegmentStore, TagIndexer}

  @type tag :: atom() | String.t()

  @type t :: %__MODULE__{
          segments: SegmentStore.t(),
          tag_indexer: TagIndexer.t(),
          dep_graph: LiteGraph.t(),
          dirty: MapSet.t(Segment.id())
        }

  defstruct segments: SegmentStore.new(),
            tag_indexer: TagIndexer.new(),
            dep_graph: LiteGraph.new(),
            dirty: MapSet.new()

  def new, do: %__MODULE__{}

  ## Session CRUD

  @spec add_segment(t(), Segment.t()) :: {:error, :already_exists} | {:ok, t()}
  def add_segment(%__MODULE__{} = manager, %Segment{id: id} = segment) do
    with {:ok, new_segments} <- SegmentStore.add_segment(manager.segments, segment) do
      {:ok,
       %{
         manager
         | segments: new_segments,
           tag_indexer: TagIndexer.add_segment(manager.tag_indexer, id),
           dep_graph: LiteGraph.add_node(manager.dep_graph, id),
           dirty: MapSet.put(manager.dirty, id)
       }}
    end
  end

  @spec remove_segment(t(), Segment.id()) :: {:error, :not_exists} | {:ok, t()}
  def remove_segment(%__MODULE__{} = manager, seg_id) do
    with {:ok, new_segments} <- SegmentStore.remove_segment(manager.segments, seg_id) do
      {:ok, %{
        manager
        | segments: new_segments,
          tag_indexer: TagIndexer.remove_segment(manager.tag_indexer, seg_id),
          dep_graph: LiteGraph.remove_node(manager.dep_graph, seg_id),
          dirty: MapSet.delete(manager.dirty, seg_id)
      }}
    end
  end

  @spec get_segment(t(), Segment.id()) :: {:error, :not_exists} | {:ok, Segment.t()}
  def get_segment(%__MODULE__{segments: segs}, seg_id) do
    SegmentStore.get_segment(segs, seg_id)
  end

  # segment_ids/1
  @spec segment_ids(t()) :: [Segment.id()]
  def segment_ids(%__MODULE__{segments: segs}), do: SegmentStore.exist_segments(segs)

  ## Tag related

  # Tag's CRUD

  @spec create_tag(t(), tag()) :: t()
  def create_tag(%__MODULE__{} = mgr, new_tag) do
    %{mgr | tag_indexer: TagIndexer.create_tag(mgr.tag_indexer, new_tag)}
  end

  @spec delete_tag(t(), tag()) :: t()
  def delete_tag(%__MODULE__{} = mgr, removed_tag) do
    %{mgr | tag_indexer: TagIndexer.remove_tag(mgr.tag_indexer, removed_tag)}
  end

  @spec apply_tag(t(), tag(), [Segment.id()] | Segment.id()) :: t()
  def apply_tag(%__MODULE__{} = manager, tag, seg_ids) do
    clean_segments_ids =
      seg_ids
      |> List.wrap()
      |> Enum.filter(&SegmentStore.exists?(manager.segments, &1))

    %{manager | tag_indexer: TagIndexer.apply_tag(manager.tag_indexer, tag, clean_segments_ids)}
  end

  @spec divest_tag(t(), tag(), [Segment.id()] | Segment.id()) :: t()
  def divest_tag(%__MODULE__{} = manager, tag, seg_ids) do
    %{manager | tag_indexer: TagIndexer.divest_tag(manager.tag_indexer, tag, seg_ids)}
  end

  # query_tag
  # query_by_tags/3
  @spec query_by_tags(t(), maybe_improper_list(), :union | :intersection) :: any()
  def query_by_tags(%__MODULE__{} = manager, tags, mode) do
    TagIndexer.query_by_tags(manager.tag_indexer, tags, mode)
  end

  ## Dependency Management

  # Mono

  def add_dependency(%__MODULE__{} = manager, from_seg_id, to_seg_id) do
    new_graph = LiteGraph.add_edge(manager.dep_graph, from_seg_id, to_seg_id)

    manager = %{manager | dep_graph: new_graph}

    if MapSet.member?(manager.dirty, from_seg_id) do
      propagate_dirty(manager, [to_seg_id])
    else
      manager
    end
  end

  def remove_dependency(%__MODULE__{} = manager, from_seg_id, to_seg_id) do
    new_graph = LiteGraph.remove_edge(manager.dep_graph, from_seg_id, to_seg_id)

    manager = %{manager | dep_graph: new_graph}

    if MapSet.member?(manager.dirty, from_seg_id) do
      propagate_dirty(manager, [to_seg_id])
    else
      manager
    end
  end

  # tag X dependency

  def add_tag_dependency(
        %__MODULE__{} = manager,
        {source_tag, source_mode},
        {target_tag, target_mode}
      ) do
    sources = query_by_tags(manager, List.wrap(source_tag), source_mode)
    targets = query_by_tags(manager, List.wrap(target_tag), target_mode)

    # apply Cartesian product
    Enum.reduce(sources, manager, fn src_id, acc_manager ->
      Enum.reduce(targets, acc_manager, fn tgt_id, inner_manager ->
        add_dependency(inner_manager, src_id, tgt_id)
      end)
    end)
  end

  def remove_tag_dependency(
        %__MODULE__{} = manager,
        {source_tag, source_mode},
        {target_tag, target_mode}
      ) do
    sources = query_by_tags(manager, List.wrap(source_tag), source_mode)
    targets = query_by_tags(manager, List.wrap(target_tag), target_mode)

    # same as add_tag_dependency
    Enum.reduce(sources, manager, fn src_id, acc_manager ->
      Enum.reduce(targets, acc_manager, fn tgt_id, inner_manager ->
        remove_dependency(inner_manager, src_id, tgt_id)
      end)
    end)
  end

  ## Operations(with Dirty Propogation) & Dispatch

  # apply_operation/3
  def apply_operation(%__MODULE__{} = manager, segment_id, op) do
    with {:ok, new_segments} <-
           SegmentStore.update_segment(manager.segments, segment_id, fn seg ->
             Segment.apply_operation(seg, op)
           end) do
      op_with_dirty_propagation(manager, new_segments, segment_id)
    else
      _ -> manager
    end
  end

  # undo/2
  def undo(%__MODULE__{} = manager, segment_id) do
    with {:ok, new_segments} <-
           SegmentStore.update_segment(manager.segments, segment_id, &Segment.undo/1) do
      op_with_dirty_propagation(manager, new_segments, segment_id)
    else
      _ -> manager
    end
  end

  # redo/2
  def redo(%__MODULE__{} = manager, segment_id) do
    with {:ok, new_segments} <-
           SegmentStore.update_segment(manager.segments, segment_id, &Segment.redo/1) do
      op_with_dirty_propagation(manager, new_segments, segment_id)
    else
      _ -> manager
    end
  end

  defp op_with_dirty_propagation(manager, new_segments, segment_id) do
    manager
    |> put_in([Access.key(:segments)], new_segments)
    |> propagate_dirty([segment_id])
  end

  # grouped_dispatch_order/2 (manager, condition)
  def grouped_dispatch_order(%__MODULE__{} = mgr, filter_tags \\ []) do
    initial_targets =
      if filter_tags == [] do
        mgr.dirty
      else
        query_by_tags(mgr, filter_tags, :intersection)
      end

    if MapSet.size(initial_targets) == 0 do
      {:ok, []}
    else
      required_set =
        Enum.reduce(initial_targets, initial_targets, fn seg_id, acc ->
          upstreams = LiteGraph.dependencies(mgr.dep_graph, seg_id)
          dirty_upstreams = MapSet.intersection(upstreams, mgr.dirty)
          MapSet.union(acc, dirty_upstreams)
        end)

      case LiteGraph.topological_sort(mgr.dep_graph) do
        {:ok, global_order} ->
          ordered_required = Enum.filter(global_order, &MapSet.member?(required_set, &1))

          stages = build_stages(ordered_required, required_set, mgr.dep_graph)
          {:ok, stages}

        {:error, _} = err ->
          err
      end
    end
  end

  def clear_dirty(%__MODULE__{} = mgr, rendered_seg_ids) do
    %{mgr | dirty: MapSet.difference(mgr.dirty, MapSet.new(rendered_seg_ids))}
  end

  ## Helper

  # dump all data
  def dump(%__MODULE__{} = manager), do: manager

  ## Private

  defp propagate_dirty(%__MODULE__{} = manager, initial_dirty_ids) do
    affected_ids =
      Enum.reduce(initial_dirty_ids, MapSet.new(), fn id, acc ->
        MapSet.union(acc, LiteGraph.dependents(manager.dep_graph, id))
      end)

    %{
      manager
      | dirty:
          MapSet.union(manager.dirty, MapSet.union(affected_ids, MapSet.new(initial_dirty_ids)))
    }
  end

  defp build_stages(ordered_required, required_set, dep_graph) do
    {_, depth_map} =
      Enum.reduce(ordered_required, {dep_graph, %{}}, fn id, {g, depths} ->
        in_deps =
          Map.get(g.in_adj, id, [])
          |> Enum.filter(&MapSet.member?(required_set, &1))

        node_depth =
          if in_deps == [] do
            0
          else
            (in_deps |> Enum.map(&Map.fetch!(depths, &1)) |> Enum.max()) + 1
          end

        {g, Map.put(depths, id, node_depth)}
      end)

    # Result: %{0 => [A, B], 1 => [C]} -> [[A, B], [C]]
    depth_map
    |> Enum.group_by(fn {_id, depth} -> depth end, fn {id, _depth} -> id end)
    |> Enum.sort_by(fn {depth, _ids} -> depth end)
    |> Enum.map(fn {_depth, ids} -> ids end)
  end
end
