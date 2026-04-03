defmodule Quincunx.Editor.SegmentStore do
  alias Quincunx.Editor.Segment

  @type t :: %{Segment.id() => Segment.t()}

  def add_segment(store, %Segment{id: segment_id} = new_segment) do
    if Map.has_key?(store.segments, segment_id) do
      {:error, :already_exists}
    else
      {:ok, Map.put(store, segment_id, new_segment)}
    end
  end

  def remove_segment(store, segment_id) do
    if Map.has_key?(store, segment_id) do
      {:ok, Map.delete(store, segment_id)}
    else
      {:error, :not_exists}
    end
  end

  def update_segment(store, segment_id, update_fn) do
    with true <- Map.has_key?(store, segment_id) do
      new_seg = update_fn.(store[segment_id])

      cond do
        new_seg.id == segment_id ->
          {:ok, %{store | segment_id => new_seg}}

        Map.has_key?(store, new_seg.id) == true ->
          {:error, :segment_id_conflict}

        true ->
          new_store = Map.delete(store, segment_id) |> Map.put(new_seg.id, new_seg)
          # Used to align tag/dependencies index
          {:segment_id_changed, new_store}
      end
    else
      false -> {:error, :not_exists}
    end
  end
end
