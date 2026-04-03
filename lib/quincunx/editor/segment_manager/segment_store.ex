defmodule Quincunx.Editor.SegmentStore do
  alias Quincunx.Editor.Segment

  @type t :: %{Segment.id() => Segment.t()}

  @spec add_segment(t(), Segment.t()) ::
          {:error, :already_exists} | {:ok, t()}
  def add_segment(store, %Segment{id: segment_id} = new_segment) do
    if Map.has_key?(store.segments, segment_id) do
      {:error, :already_exists}
    else
      {:ok, Map.put(store, segment_id, new_segment)}
    end
  end

  @spec remove_segment(t(), Segment.id()) :: {:error, :not_exists} | {:ok, t()}
  def remove_segment(store, segment_id) do
    if Map.has_key?(store, segment_id) do
      {:ok, Map.delete(store, segment_id)}
    else
      {:error, :not_exists}
    end
  end

  @spec update_segment(t(), Segment.id(), (Segment.t() -> Segment.t())) ::
          {:error, :not_exists | :segment_id_conflict}
          | {:ok, t()}
          | {:segment_id_changed, t()}
  def update_segment(store, segment_id, update_fn) do
    with true <- Map.has_key?(store, segment_id) do
      new_seg = update_fn.(store[segment_id])

      # If some function modified the ID.
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
