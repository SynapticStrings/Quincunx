defmodule Quincunx.Session.Server do
  @moduledoc """
  Provide a GenServer.
  """
  use GenServer

  alias Quincunx.Editor.Segment
  alias Quincunx.Session.Storage
  alias Quincunx.Renderer.{Planner, Blackboard}

  defmodule State do
    @type t :: %__MODULE__{
            session_id: term(),
            segments: %{Segment.id() => Segment.t()},
            dirty: MapSet.t(Segment.id()),
            blackboard: Blackboard.t(),
            storage: Storage.t() | nil,
            last_plan: Planner.Plan.t() | nil,
            subscribers: [pid()]
          }
    defstruct [
      :session_id,
      :storage,
      :last_plan,
      segments: %{},
      dirty: MapSet.new(),
      blackboard: nil,
      subscribers: []
    ]
  end

  ## PUBLIC API ##

  ## CALLBACKs

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    storage = if Keyword.get(opts, :enable_cache, true), do: Storage.new(), else: nil

    {:ok,
     %State{
       session_id: session_id,
       storage: storage,
       blackboard: Blackboard.new(session_id)
     }}
  end

  # handle_call :add_segment

  # handle_call :remove_segment
end
