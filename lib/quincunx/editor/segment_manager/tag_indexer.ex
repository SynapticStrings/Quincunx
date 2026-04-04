defmodule Quincunx.Editor.TagIndexer do
  alias Quincunx.Editor.Segment

  @type tag :: atom() | String.t()
  @type t :: %__MODULE__{
          # Forward Index => Segment's tag(s)
          segment_index: %{Segment.id() => MapSet.t(tag())},
          # Backward Index => Tag include segments
          tag_index: %{tag() => MapSet.t(Segment.id())}
        }
  defstruct segment_index: %{}, tag_index: %{}

  def new, do: %__MODULE__{}

  ## Segment Related

  def add_segment(%__MODULE__{} = indexer, new_segment_id) do
    %{indexer | segment_index: Map.put(indexer.segment_index, new_segment_id, MapSet.new())}
  end

  def remove_segment(%__MODULE__{} = indexer, new_segment_id) do
    tags = Map.get(indexer.segment_index, new_segment_id, MapSet.new())

    new_tag_index =
      Enum.reduce(tags, indexer.tag_index, fn tag, acc ->
        Map.update(acc, tag, MapSet.new(), &MapSet.delete(&1, new_segment_id))
      end)

    %{
      indexer
      | segment_index: Map.delete(indexer.segment_index, new_segment_id),
        tag_index: new_tag_index
    }
  end

  ## Tag's CRUD

  def create_tag(%__MODULE__{} = indexer, tag) do
    put_in(indexer, [:tag_index], %{tag => MapSet.new()})
  end

  def remove_tag(%__MODULE__{} = indexer, tag) do
    current_segment_index = Map.get(indexer.tag_index, tag)

    new_segment_index =
      if MapSet.size(current_segment_index) > 0 do
        Enum.reduce(current_segment_index, indexer.segment_index, fn seg_id, acc ->
          %{acc | seg_id => MapSet.delete(acc[seg_id], tag)}
        end)
      else
        indexer.segment_index
      end

    %{indexer | segment_index: new_segment_index, tag_index: Map.delete(indexer.tag_index, tag)}
  end

  def get_tags(%__MODULE__{tag_index: index}), do: Map.keys(index)

  def get_tags(%__MODULE__{segment_index: index}, segment_id), do: Map.get(index, segment_id, MapSet.new())

  def get_segments(%__MODULE__{tag_index: index}, tag) do
    Map.get(index, tag, MapSet.new())
  end

  def apply_tag(%__MODULE__{} = indexer, tag, segment_ids) do
    # With automatic creation
    segment_ids
    |> List.wrap()
    |> Enum.reduce(indexer, fn segment_id, acc ->
      %{
        acc
        | segment_index:
            Map.update(acc.segment_index, segment_id, MapSet.new([tag]), &MapSet.put(&1, tag)),
          tag_index:
            Map.update(acc.tag_index, tag, MapSet.new([segment_id]), &MapSet.put(&1, segment_id))
      }
    end)
  end

  def divest_tag(%__MODULE__{} = indexer, tag, seg_ids) do
    Enum.reduce(seg_ids, indexer, fn seg_id, acc ->
      %{
        acc
        | segment_index:
            Map.update(acc.segment_index, seg_id, MapSet.new(), &MapSet.delete(&1, tag)),
          tag_index: Map.update(acc.tag_index, tag, MapSet.new(), &MapSet.delete(&1, seg_id))
      }
    end)
  end

  def query_by_tags(indexer, tags, mode \\ :union)

  def query_by_tags(%__MODULE__{} = _indexer, [], _mode), do: MapSet.new()

  def query_by_tags(%__MODULE__{} = indexer, tags, mode) when is_list(tags) do
    new_tags =
      tags
      |> Enum.map(&Map.get(indexer.tag_index, &1, MapSet.new()))

    case mode do
      :union -> Enum.reduce(new_tags, &MapSet.union/2)
      :intersection -> Enum.reduce(new_tags, &MapSet.intersection/2)
    end
  end
end
