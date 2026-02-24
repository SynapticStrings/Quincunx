defmodule Quincunx.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """
  alias Quincunx.Dependency
  alias Quincunx.Segment.RecorderAdapter

  @type snapshot :: Orchid.Scheduler.Context.param_map()

  @type t :: %__MODULE__{
          id: String.t() | atom(),
          dependency: nil | Dependency.t(),
          record: RecorderAdapter.record(),
          cursor: RecorderAdapter.cursor(),
          snapshots: snapshot(),
          recorder_adapter: module(),
          extra: map()
        }
  defstruct id: nil,
            dependency: nil,
            record: [],
            cursor: 0,
            snapshots: %{},
            recorder_adapter: Quincunx.Segment.LinearRecorder,
            extra: %{}
end
