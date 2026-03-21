defmodule Quincunx.Lily.History do
  defmodule Operation do
    alias Quincunx.Lily.Graph.{Node, Edge, PortRef}

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
            {op :: atom(), PortRef.t(), data :: any()}
            | {:remove_interventions, PortRef.t()}

    @type t :: topology_mutation() | data_interventions() | input_declar()
  end

  alias Quincunx.Lily.Graph

  @type inputs_bundle :: %{
          # :inputs => %{Graph.PortRef.t() => any()},
          # :overrides => %{Graph.PortRef.t() => any()},
          # :offsets => %{Graph.PortRef.t() => any()},
          # :masks => %{Graph.PortRef.t() => any()},
          # optional(any()) => any()
          binary() => %{Graph.PortRef.t() => any()}
        }

  @type effective_state :: {Graph.t(), inputs_bundle()}

  @type t :: %__MODULE__{
          # 越新的操作越靠前 (Head)
          undo_stack: [Operation.t()],
          # 越靠近当前时间点的“未来”越靠前
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
  将所有的历史记录（过去）按时间顺序叠加到 base_graph 上。
  输出 Compiler 和 Orchid 真正需要的有效状态。
  """
  @spec resolve(Graph.t(), t()) :: effective_state()
  def resolve(%Graph{} = base_graph, %__MODULE__{undo_stack: undo_stack}) do
    initial_state = %{graph: base_graph}

    undo_stack
    |> Enum.reverse()
    |> Enum.reduce(initial_state, &apply_operation/2)
    |> Map.pop(:graph)
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

  defp apply_operation({:set_input, port_ref, data}, state) do
    apply_operation({:input, port_ref, data}, state)
  end

  defp apply_operation({intervention_name, {:port, _, _} = port_ref, value}, state)
       when is_atom(intervention_name) do
    apply_operation({"#{Atom.to_string(intervention_name)}s", port_ref, value}, state)
  end

  defp apply_operation({intervention_name, {:port, _, _} = port_ref, value}, state)
       when is_binary(intervention_name) do
    new_intervention =
      state
      |> Map.get(intervention_name, %{})
      |> Map.put(port_ref, value)

    Map.put(state, intervention_name, new_intervention)
  end

  defp apply_operation({:remove_input, port_ref}, state) do
    remove_intervention("inputs", port_ref, state)
  end

  defp apply_operation({:remove_interventions, {:port, _, _} = port_ref}, state) do
    state
    |> Map.keys()
    |> List.delete(:graph)
    |> Enum.reduce(state, &remove_intervention(&1, port_ref, &2))
  end

  defp remove_intervention(intervation_name, {:port, _, _} = port_ref, state) do
    case Map.get(state, intervation_name) do
      %{} ->
        %{state | intervation_name => Map.get(state, intervation_name) |> Map.delete(port_ref)}

      nil ->
        state
    end
  end
end
