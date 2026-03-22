defmodule Quincunx.Renderer.Blackboard do
  alias Quincunx.{Segment, Storage}
  alias Quincunx.Lily.Graph.PortRef

  @type t :: %__MODULE__{
          segment_id: Segment.id(),
          memory: %{PortRef.t() => Orchid.Param.t() | any()},
          cache_ref: nil | Storage.t()
        }

  defstruct [:segment_id, memory: %{}, cache_ref: nil]

  @spec new(Segment.id()) :: t()
  def new(segment_id), do: %__MODULE__{segment_id: segment_id, memory: %{}}

  @spec put(t(), %{PortRef.t() => Orchid.Param.t()}) :: t()
  def put(%__MODULE__{} = board, new_data) when is_map(new_data) do
    %{board | memory: Map.merge(board.memory, new_data)}
  end

  @spec fetch_requires(t(), [PortRef.t()]) :: %{PortRef.t() => Orchid.Param.t()}
  def fetch_requires(%__MODULE__{memory: mem}, required_keys) do
    required_keys
    |> Enum.map(fn key -> {key, Map.get(mem, key)} end)
    |> Enum.into(%{})
  end
end
