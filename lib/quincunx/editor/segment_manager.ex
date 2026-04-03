defmodule Quincunx.Session.SegmentManager do
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
          # 正排索引：Segment's tag(s)
          segment_tags: %{Segment.id() => MapSet.t(tag())},
          # 倒排索引：Tag include segments
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
  def add_segment(%__MODULE__{} = mgr, %Segment{id: id} = seg) do
    if Map.has_key?(mgr.segments, id) do
      {:error, :already_exists}
    else
      {:ok,
       %{
         mgr
         | segments: Map.put(mgr.segments, id, seg),
           dep_graph: LiteGraph.add_node(mgr.dep_graph, id),
           dirty: MapSet.put(mgr.dirty, id)
       }}
    end
  end

  # remove_segment/2
  def remove_segment(%__MODULE__{} = mgr, seg_id) do
    %{mgr |
      segments: Map.delete(mgr.segments, seg_id),
      dep_graph: LiteGraph.remove_node(mgr.dep_graph, seg_id),
      dirty: MapSet.delete(mgr.dirty, seg_id)
    }
  end

  # get_segment/2
  def get_segment(%__MODULE__{segments: segs}, seg_id) do
    Map.fetch(segs, seg_id)
    |> case do
      :error -> {:error, :segement_not_exists}
      ok_seg -> ok_seg
    end
  end

  # segment_ids/1
  def segment_ids(%__MODULE__{segments: segs}), do: Map.keys(segs)

  ## Tag related

  # Tag's CRUD

  # create_tag/2

  # delete_tag/2

  # apply_tag/3
  # (manager, exists_or_not_tag, exists_segment_ids)

  # divest_tag/2

  # query_tag

  ## Complex but Useful query

  # get_segment_tags_mapper

  ## Dependency Management

  # Mono

  # add/remove

  # tag X dependency

  # add_patch/remove_patch

  ## Operations(with Dirty Propogation) & Dispatch

  # apply_operation/3
  # undo/2
  # redo/2

  # grouped_dispatch_order/2 (manager, condition)

  ## Helper

  # dump all data
  def dump(%__MODULE__{} = manager), do: manager
end
