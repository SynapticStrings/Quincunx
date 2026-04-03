defmodule Quincunx.Editor.SegmentStore do
  alias Quincunx.Editor.Segment
  alias Quincunx.Topology.LiteGraph
  alias Quincunx.Editor.SegmentManager, as: Manager

  def add_segment(%Manager{} = manager, %Segment{id: id} = seg) do
    if Map.has_key?(manager.segments, id) do
      {:error, :already_exists}
    else
      {:ok,
       %{
         manager
         | segments: Map.put(manager.segments, id, seg),
           segment_tags: Map.put(manager.segment_tags, id, MapSet.new()),
           dep_graph: LiteGraph.add_node(manager.dep_graph, id),
           dirty: MapSet.put(manager.dirty, id)
       }}
    end
  end

  def remove_segment(%Manager{} = manager, seg_id) do
    tags = Map.get(manager.segment_tags, seg_id, MapSet.new())

    new_tag_index =
      Enum.reduce(tags, manager.tag_index, fn tag, acc ->
        Map.update(acc, tag, MapSet.new(), &MapSet.delete(&1, seg_id))
      end)

    %{
      manager
      | segments: Map.delete(manager.segments, seg_id),
        segment_tags: Map.delete(manager.segment_tags, seg_id),
        tag_index: new_tag_index,
        dep_graph: LiteGraph.remove_node(manager.dep_graph, seg_id),
        dirty: MapSet.delete(manager.dirty, seg_id)
    }
  end

  def get_segment(%Manager{segments: segs}, seg_id) do
    Map.fetch(segs, seg_id)
    |> case do
      :error -> {:error, :segement_not_exists}
      ok_seg -> ok_seg
    end
  end

  def segment_ids(%Manager{segments: segs}), do: Map.keys(segs)
end
