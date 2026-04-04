defmodule Quincunx.Editor.SegmentStore do
  alias Quincunx.Editor.Segment

  @type t :: %{Segment.id() => Segment.t()}

  ## Basics

  def new, do: %{}

  @spec exists?(t(), Segment.id()) :: boolean()
  def exists?(store, segment_id), do: Map.has_key?(store, segment_id)

  @spec exist_segments(t()) :: [Segment.id()]
  def exist_segments(store), do: Map.keys(store)

  ## CRUD

  @spec add_segment(t(), Segment.t()) ::
          {:error, :already_exists} | {:ok, t()}
  def add_segment(store, %Segment{id: segment_id} = new_segment) do
    if exists?(store, segment_id) do
      {:error, :already_exists}
    else
      {:ok, Map.put(store, segment_id, new_segment)}
    end
  end

  @spec get_segment(t(), Segment.id()) :: {:ok, Segment.t()} | {:error, :not_exists}
  def get_segment(store, segment_id) do
    Map.fetch(store, segment_id)
    |> case do
      :error -> {:error, :not_exists}
      ok_seg -> ok_seg
    end
  end

  @spec remove_segment(t(), Segment.id()) :: {:error, :not_exists} | {:ok, t()}
  def remove_segment(store, segment_id) do
    if exists?(store, segment_id) do
      {:ok, Map.delete(store, segment_id)}
    else
      {:error, :not_exists}
    end
  end

  @spec update_segment(t(), Segment.id(), (Segment.t() -> Segment.t())) ::
          {:error, :not_exists | :segment_id_conflict | :segment_id_changed}
          | {:ok, t()}
  def update_segment(store, segment_id, update_fn) do
    with true <- exists?(store, segment_id) do
      new_seg = update_fn.(store[segment_id])

      # If some function modified the ID.
      cond do
        new_seg.id == segment_id ->
          {:ok, %{store | segment_id => new_seg}}

        exists?(store, new_seg.id) ->
          {:error, :segment_id_conflict}

        true ->
          {:error, :segment_id_changed}
      end
    else
      false -> {:error, :not_exists}
    end
  end
end
