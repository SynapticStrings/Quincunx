defmodule Quincunx.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Lily.History.Operation
  alias Lily.{Graph, History, Compiler, Graph.Cluster}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          base_graph: Graph.t(),
          history: History.t(),
          cluster_declara: Cluster.t(),
          snapshots: %{optional(atom()) => any()},
          extra: map()
        }

  defstruct [
    :id,
    base_graph: %Graph{},
    history: %History{},
    cluster_declara: %Cluster{},
    snapshots: %{},
    extra: %{}
  ]

  @spec new(id(), Graph.t()) :: t()
  @spec new(id(), Graph.t(), Cluster.t()) :: t()
  def new(id, base_graph, cluster_declara \\ %Cluster{}) do
    %__MODULE__{
      id: id,
      base_graph: base_graph,
      history: History.new(),
      cluster_declara: cluster_declara
    }
  end

  @spec apply_operation(t(), Operation.t()) :: t()
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

  @spec compile_to_recipes(t()) :: {:error, :cycle_detected} | {:ok, list()}
  def compile_to_recipes(%__MODULE__{} = segment) do
    %{graph: final_graph, inputs: inputs, overrides: overrides, offsets: offsets} =
      History.resolve(segment.base_graph, segment.history)

    final_graph
    |> Compiler.compile(segment.cluster_declara)
    |> case do
      {:ok, recipe} ->
        Compiler.bind_interventions(recipe, %{
          inputs: inputs,
          overrides: overrides,
          offsets: offsets
        })

      err ->
        err
    end
  end
end
