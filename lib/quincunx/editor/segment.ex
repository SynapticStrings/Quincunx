defmodule Quincunx.Editor.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Quincunx.Editor.History
  alias Quincunx.Topology.{Graph, Cluster}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          graph: Graph.t(),
          cluster: Cluster.t(),
          history: History.t(),
          extra: map()
        }

  defstruct [
    :id,
    graph: %Graph{},
    cluster: %Cluster{},
    history: %History{},
    extra: %{}
  ]

  @spec new(id(), Graph.t()) :: t()
  @spec new(id(), Graph.t(), Cluster.t()) :: t()
  def new(id, graph, cluster_declara \\ %Cluster{}) do
    %__MODULE__{
      id: id,
      graph: graph,
      cluster: cluster_declara,
      history: History.new()
    }
  end

  @spec apply_operation(t(), History.Operation.t()) :: t()
  def apply_operation(%__MODULE__{} = segment, operation) do
    %{segment | history: History.push(segment.history, operation)}
  end

  @spec undo(t()) :: t()
  def undo(%__MODULE__{} = segment) do
    %{segment | history: History.undo(segment.history)}
  end

  @spec redo(t()) :: t()
  def redo(%__MODULE__{} = segment) do
    %{segment | history: History.redo(segment.history)}
  end
end
