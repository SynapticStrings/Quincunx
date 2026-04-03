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

  @type tag :: atom() | String.t()

  @type t :: %__MODULE__{
          segments: %{Segment.id() => Segment.t()},
          # Forward Index => Segment's tag(s)
          segment_tags: %{Segment.id() => MapSet.t(tag())},
          # Backward Index => Tag include segments
          tag_index: %{tag() => MapSet.t(Segment.id())},
          dep_graph: LiteGraph.t(),
          dirty: MapSet.t(Segment.id())
        }

  defstruct segments: %{},
            segment_tags: %{},
            tag_index: %{},
            dep_graph: LiteGraph.new(),
            dirty: MapSet.new()

  def new, do: %__MODULE__{}

  ## Session CRUD

  # add_segment/3
  defdelegate add_segment(manager, seg), to: Quincunx.Editor.SegmentStore

  # remove_segment/2
  defdelegate remove_segment(manager, seg_id), to: Quincunx.Editor.SegmentStore

  # get_segment/2
  defdelegate get_segment(manager, seg_id), to: Quincunx.Editor.SegmentStore

  # segment_ids/1
  defdelegate segment_ids(manager), to: Quincunx.Editor.SegmentStore

  ## Tag related

  # Tag's CRUD

  # create_tag/2

  # delete_tag/2

  # apply_tag/3
  # (manager, exists_or_not_tag, exists_segment_ids)
  def apply_tag(%__MODULE__{} = manager, tag, seg_ids) do
    Enum.reduce(seg_ids, manager, fn seg_id, acc ->
      if Map.has_key?(acc.segments, seg_id) do
        %{
          acc
          | segment_tags:
              Map.update(acc.segment_tags, seg_id, MapSet.new([tag]), &MapSet.put(&1, tag)),
            tag_index:
              Map.update(acc.tag_index, tag, MapSet.new([seg_id]), &MapSet.put(&1, seg_id))
        }
      else
        acc
      end
    end)
  end

  # divest_tag/2
  def divest_tag(%__MODULE__{} = manager, tag, seg_ids) do
    Enum.reduce(seg_ids, manager, fn seg_id, acc ->
      %{
        acc
        | segment_tags:
            Map.update(acc.segment_tags, seg_id, MapSet.new(), &MapSet.delete(&1, tag)),
          tag_index: Map.update(acc.tag_index, tag, MapSet.new(), &MapSet.delete(&1, seg_id))
      }
    end)
  end

  # query_tag
  # query_by_tags/3
  def query_by_tags(%__MODULE__{} = manager, tags, mode \\ :union) when is_list(tags) do
    new_tags =
      tags
      |> Enum.map(&Map.get(manager.tag_index, &1, MapSet.new()))

    case mode do
      :union -> Enum.reduce(new_tags, &MapSet.union/2)
      :intersection -> Enum.reduce(new_tags, &MapSet.intersection/2)
    end
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
  def apply_operation(%__MODULE__{} = manager, seg_id, op) do
    case Map.fetch(manager.segments, seg_id) do
      {:ok, seg} ->
        Segment.apply_operation(seg, op)
        |> then(&op_with_dirty_propogation(manager, seg_id, &1))

      :error ->
        manager
    end
  end

  # undo/2
  def undo(%__MODULE__{} = manager, seg_id) do
    case Map.fetch(manager.segments, seg_id) do
      {:ok, seg} ->
        op_with_dirty_propogation(manager, seg_id, Segment.undo(seg))

      :error ->
        manager
    end
  end

  # redo/2
  def redo(%__MODULE__{} = manager, seg_id) do
    case Map.fetch(manager.segments, seg_id) do
      {:ok, seg} ->
        op_with_dirty_propogation(manager, seg_id, Segment.redo(seg))

      :error ->
        manager
    end
  end

  defp op_with_dirty_propogation(manager, seg_id, new_seg) do
    manager
    |> put_in([Access.key(:segments), seg_id], new_seg)
    |> propagate_dirty([seg_id])
  end

  # grouped_dispatch_order/2 (manager, condition)
  def grouped_dispatch_order(%__MODULE__{} = mgr, filter_tags \\ []) do
    initial_targets  =
      if filter_tags == [] do
        mgr.dirty
      else
        query_by_tags(mgr, filter_tags, :intersection)
      end

    if MapSet.size(initial_targets ) == 0 do
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
    affected_ids = LiteGraph.dependents(manager.dep_graph, initial_dirty_ids)

    %{manager | dirty: MapSet.union(manager.dirty, MapSet.new(affected_ids))}
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
