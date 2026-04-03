defmodule Quincunx.Editor.TagIndexer do
  alias Quincunx.Editor.Segment

  @type tag :: atom() | String.t()
  @type t :: %__MODULE__{
          # Forward Index => Segment's tag(s)
          segment_index: %{Segment.id() => MapSet.t(tag())},
          # Backward Index => Tag include segments
          tag_index: %{tag() => MapSet.t(Segment.id())}
        }
  defstruct [:segment_index, :tag_index]

  def new, do: %__MODULE__{}

  # def when_add_segment

  # def when_remove_segment
end
