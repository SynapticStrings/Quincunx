defmodule Quincunx.Editor.History do
  @moduledoc """
  ...
  """

  defmodule Operation do
    @moduledoc "To record operations."

    alias Quincunx.Topology.Graph.{Node, Edge, PortRef}

    @type intervention_type :: :input | :override | :offset | :mask | atom()

    @typedoc "This indicates the change in the DAG topology."
    @type topology_mutation ::
            {:add_node, Node.t()}
            | {:update_node, Node.id(),
               node_or_update_funtion :: Node.t() | (Node.t() -> Node.t())}
            | {:remove_node, Node.id()}
            | {:add_edge, Edge.t()}
            | {:remove_edge, Edge.t()}

    @typedoc "Record the data intervention operations."
    @type data_interventions ::
            {:set_intervention, PortRef.t(), intervention_type(), data :: any()}
            | {:remove_intervention, PortRef.t(), intervention_type()}
            | {:clear_interventions, PortRef.t()}
            | nil

    @type t :: topology_mutation() | data_interventions()

    # Because the subsequent context needs to preserve the graph structure and RecipeBundle
    # as a cache (or snapshot), it is necessary to record whether the update operations(compared to the snapshot)
    # involve the topology of the execution graph (excluding the cluster options).
    @spec topology?(t()) :: boolean()
    def topology?(op)
        when elem(op, 0) in [
               :add_node,
               :update_node,
               :remove_node,
               :add_edge,
               :remove_edge
             ],
        do: true

    def topology?(_), do: false
  end

  @type t :: %__MODULE__{
          # new as head
          undo_stack: [Operation.t()],
          # [redo_immed, ...]
          redo_stack: [Operation.t()]
        }

  defstruct undo_stack: [], redo_stack: []

  @doc "Initialize a new History record container."
  def new, do: %__MODULE__{}

  @spec push(t(), Operation.t()) :: t()
  def push(%__MODULE__{undo_stack: undo} = history, op) do
    %{history | undo_stack: [op | undo], redo_stack: []}
  end

  # Let me explain why undo & redo required pop operation
  # because it required pass Operation.topology?/1 or other function
  # to dicided how to do next.

  @spec undo(t()) :: {t(), Operation.t()}
  def undo(%__MODULE__{undo_stack: []} = history), do: {history, nil}

  def undo(%__MODULE__{undo_stack: [last_op | rest_undo], redo_stack: redo} = history) do
    {%{history | undo_stack: rest_undo, redo_stack: [last_op | redo]}, last_op}
  end

  @spec redo(t()) :: {t(), Operation.t()}
  def redo(%__MODULE__{redo_stack: []} = history), do: {history, nil}

  def redo(%__MODULE__{undo_stack: undo, redo_stack: [next_op | rest_redo]} = history) do
    {%{history | undo_stack: [next_op | undo], redo_stack: rest_redo}, next_op}
  end
end
