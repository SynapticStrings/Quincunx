defmodule Quincunx.Renderer.Blackboard do
  @moduledoc """
  Runtime memory view for incremental generation results.

  Blackboard acts as the **read/write interface** between Workers and the
  underlying `Quincunx.Storage.Behaviour` implementation. It holds computed
  results (outputs) and user-provided inputs, keyed by segment address.
  """

  alias Quincunx.Editor.Segment

  @type session_id :: term()
  @type addr :: {Segment.id(), Orchid.Step.io_key()}

  @type t :: %__MODULE__{
          session_id: session_id(),
          memory: %{addr() => Orchid.Param.t() | any()}
        }

  defstruct [:session_id, memory: %{}]

  @spec new(session_id()) :: t()
  def new(session_id), do: %__MODULE__{session_id: session_id, memory: %{}}

  @spec put(t(), %{addr() => Orchid.Param.t()}) :: t()
  def put(%__MODULE__{} = board, new_data) when is_map(new_data) do
    %{board | memory: Map.merge(board.memory, new_data)}
  end

  @spec fetch_contents(t(), [addr()]) :: %{addr() => Orchid.Param.t()}
  def fetch_contents(%__MODULE__{memory: mem}, required_keys) do
    required_keys
    |> Enum.map(fn key -> {key, Map.get(mem, key)} end)
    |> Enum.into(%{})
  end

  @spec fetch_contents(t(), Segment.id()) :: %{addr() => Orchid.Param.t()}
  def fetch_via_session(%__MODULE__{memory: mem} = blackboard, segment_id) do
    Map.keys(mem)
    |> Enum.filter(fn {ssid, _} -> segment_id == ssid end)
    |> then(&fetch_contents(blackboard, &1))
  end
end
