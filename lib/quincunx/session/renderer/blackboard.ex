defmodule Quincunx.Session.Renderer.Blackboard do
  alias Quincunx.Session.Segment
  alias Lily.Graph.Portkey

  @type t :: %__MODULE__{
          segment_id: Segment.id(),
          memory: %{Portkey.t() => Orchid.Param.t() | any()}
        }

  defstruct [:segment_id, memory: %{}]

  @spec new(any()) :: t()
  def new(segment_id), do: %__MODULE__{segment_id: segment_id, memory: %{}}

  @spec put(t(), %{Portkey.t() => Orchid.Param.t()}) :: t()
  def put(%__MODULE__{} = board, new_data) when is_map(new_data) do
    %{board | memory: Map.merge(board.memory, new_data)}
  end

  @spec fetch_requires(t(), [Portkey.t()]) :: %{Portkey.t() => Orchid.Param.t()}
  def fetch_requires(%__MODULE__{memory: mem}, required_keys) do
    required_keys
    |> Enum.map(fn key -> {key, Map.get(mem, key)} end)
    |> Enum.into(%{})
  end
end
