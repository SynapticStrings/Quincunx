defmodule Quincunx.Editor.History do
  defmodule Operation do
    alias Quincunx.Topology.Graph.{Node, Edge, PortRef}

    @type intervention_type :: :input | :override | :offset | :mask | atom()

    @type topology_mutation ::
            {:add_node, Node.t()}
            | {:update_node, Node.id(),
               node_or_update_funtion :: Node.t() | (Node.t() -> Node.t())}
            | {:remove_node, Node.id()}
            | {:add_edge, Edge.t()}
            | {:remove_edge, Edge.t()}

    @type input_declar ::
            {:set_input, PortRef.t(), data :: any()}
            | {:remove_input, PortRef.t()}

    @type data_interventions ::
            {:set_intervention, PortRef.t(), intervention_type(), data :: any()}
            | {:remove_intervention, PortRef.t(), intervention_type()}
            | {:clear_interventions, PortRef.t()}

    @type t :: topology_mutation() | data_interventions() | input_declar()
  end

  alias Quincunx.Topology.Graph

  @type interventions_map :: %{
          Graph.PortRef.t() => %{Operation.intervention_type() => any()}
        }

  @type effective_state :: {Graph.t(), interventions_map()}

  @type t :: %__MODULE__{
          # new as head
          undo_stack: [Operation.t()],
          # [redo_immed, ...]
          redo_stack: [Operation.t()]
        }

  defstruct undo_stack: [], redo_stack: []

  @doc "Initialize a new History record container."
  def new, do: %__MODULE__{}

  @spec push(t(), any()) :: t()
  def push(%__MODULE__{undo_stack: undo} = history, op) do
    %{history | undo_stack: [op | undo], redo_stack: []}
  end

  @spec undo(t()) :: t()
  def undo(%__MODULE__{undo_stack: []} = history), do: history

  def undo(%__MODULE__{undo_stack: [last_op | rest_undo], redo_stack: redo} = history) do
    %{history | undo_stack: rest_undo, redo_stack: [last_op | redo]}
  end

  @spec redo(t()) :: t()
  def redo(%__MODULE__{redo_stack: []} = history), do: history

  def redo(%__MODULE__{undo_stack: undo, redo_stack: [next_op | rest_redo]} = history) do
    %{history | undo_stack: [next_op | undo], redo_stack: rest_redo}
  end

  @doc """
  Overlay all historical records onto the `base_graph` in chronological order.

  Output the valid states that the Compiler and Orchid need.
  """
  @spec resolve(Graph.t(), t()) :: effective_state()
  def resolve(%Graph{} = base_graph, %__MODULE__{undo_stack: undo_stack}) do
    initial_state = %{graph: base_graph, interventions: %{}}

    undo_stack
    |> Enum.reverse()
    |> Enum.reduce(initial_state, &apply_operation/2)
    |> (fn state -> {state.graph, state.interventions} end).()
  end

  defp apply_operation({:add_node, node}, state) do
    %{state | graph: Graph.add_node(state.graph, node)}
  end

  defp apply_operation({:update_node, node_id, new_node}, state) do
    %{state | graph: Graph.update_node(state.graph, node_id, new_node)}
  end

  defp apply_operation({:remove_node, node_id}, state) do
    %{state | graph: Graph.remove_node(state.graph, node_id)}
  end

  defp apply_operation({:add_edge, edge}, state) do
    %{state | graph: Graph.add_edge(state.graph, edge)}
  end

  defp apply_operation({:remove_edge, edge}, state) do
    %{state | graph: Graph.remove_edge(state.graph, edge)}
  end

  defp apply_operation({:set_intervention, port_ref, type, value}, state) do
    new_interventions =
      Map.update(
        state.interventions,
        port_ref,
        %{type => value},
        fn port_data -> Map.put(port_data, type, value) end
      )

    %{state | interventions: new_interventions}
  end

  defp apply_operation({:remove_intervention, port_ref, type}, state) do
    new_interventions =
      case Map.fetch(state.interventions, port_ref) do
        {:ok, port_data} ->
          clean_port_data = Map.delete(port_data, type)

          if map_size(clean_port_data) == 0 do
            Map.delete(state.interventions, port_ref)
          else
            Map.put(state.interventions, port_ref, clean_port_data)
          end

        :error ->
          state.interventions
      end

    %{state | interventions: new_interventions}
  end

  defp apply_operation({:clear_interventions, port_ref}, state) do
    %{state | interventions: Map.delete(state.interventions, port_ref)}
  end
end
