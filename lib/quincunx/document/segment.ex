defmodule Quincunx.Document.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Quincunx.Document.History
  alias Quincunx.Topology.{Graph, Cluster}

  @type interventions_map :: %{
          Graph.PortRef.t() => OrchidIntervention.intervention_spec()
        }

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          name: binary(),
          graph: Graph.t(Orchid.Step.implementation()),
          cluster: Cluster.t(),
          history: History.t(),
          data_interventions: interventions_map(),
          extra: map()
        }

  defstruct [
    :id,
    name: "",
    graph: %Graph{},
    cluster: %Cluster{},
    history: %History{},
    data_interventions: %{},
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

  @spec update_name(t(), String.t()) :: t()
  def update_name(segment, name) do
    %{segment | name: name}
  end

  @spec inject_graph_and_interventions(t(), Graph.t(), map(), boolean()) :: t()
  def inject_graph_and_interventions(
        %__MODULE__{} = segment,
        %Graph{} = graph,
        data_interventions,
        clear_history \\ true
      ) do
    # Combine with cache/snapshot
    history =
      if clear_history do
        %History{}
      else
        segment.history
      end

    %{segment | graph: graph, data_interventions: data_interventions, history: history}
  end

  @spec apply_operation(t(), History.Operation.t()) :: t()
  def apply_operation(%__MODULE__{} = segment, operation) do
    %{segment | history: History.push(segment.history, operation)}
  end

  @spec undo(t()) :: {t(), History.Operation.t()}
  def undo(%__MODULE__{} = segment) do
    {his, op} = History.undo(segment.history)
    {%{segment | history: his}, op}
  end

  @spec redo(t()) :: {t(), History.Operation.t()}
  def redo(%__MODULE__{} = segment) do
    {his, op} = History.redo(segment.history)
    {%{segment | history: his}, op}
  end
end
