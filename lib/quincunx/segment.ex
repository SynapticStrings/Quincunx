defmodule Quincunx.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """
  @type snapshot :: Orchid.Scheduler.Context.param_map()

  @type t :: %__MODULE__{
          id: String.t() | atom(),
          dependency: nil | Lily.Graph.t(),
          snapshots: snapshot(),
          recorder_adapter: module(),
          extra: map()
        }
  defstruct id: nil,
            dependency: nil,
            snapshots: %{},
            recorder_adapter: Lily.History,
            extra: %{}
end
