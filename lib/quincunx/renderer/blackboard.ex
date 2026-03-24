defmodule Quincunx.Renderer.Blackboard do
  alias Quincunx.Editor.Segment
  alias Quincunx.Session.Storage

  @type session_id :: term()
  @type addr :: {Segment.id(), Orchid.Step.io_key()}

  @type t :: %__MODULE__{
          session_id: session_id(),
          memory: %{addr() => Orchid.Param.t() | any()},
          cache_ref: nil | Storage.t()
        }

  defstruct [:session_id, memory: %{}, cache_ref: nil]

  @spec new(session_id(), cache_ref :: nil | Storage.t()) :: t()
  def new(session_id, cache_ref), do: %__MODULE__{session_id: session_id, memory: %{}, cache_ref: cache_ref}

  @spec put(t(), %{addr() => Orchid.Param.t()}) :: t()
  def put(%__MODULE__{} = board, new_data) when is_map(new_data) do
    %{board | memory: Map.merge(board.memory, new_data)}
  end

  @spec fetch_requires(t(), [addr()]) :: %{addr() => Orchid.Param.t()}
  def fetch_requires(%__MODULE__{memory: mem}, required_keys) do
    required_keys
    |> Enum.map(fn key -> {key, Map.get(mem, key)} end)
    |> Enum.into(%{})
  end
end
