defmodule Quincunx.Segment.LinearRecorder do
  alias Quincunx.Segment.RecorderAdapter
  alias Quincunx.Dependency.{Edge, Node}
  @behaviour RecorderAdapter

  @type record :: [RecorderAdapter.operation()]
  @type cursor :: non_neg_integer()

  @doc """
  Push a new operation.
  If the cursor is not at the end of the record (meaning we undid some steps),
  pushing a new operation will *truncate* the future (redo) history.
  """
  @impl true
  @spec push(record(), cursor(), RecorderAdapter.operation()) :: {record(), cursor()}
  def push(record, cursor, [_ | _] = operations), do: {Enum.take(record, cursor) ++ operations, cursor + length(operations)}
  def push(record, cursor, operation), do: {Enum.take(record, cursor) ++ [operation], cursor + 1}

  @doc "Move the cursor one step back."
  @impl true
  @spec undo(record(), cursor()) :: cursor()
  def undo(_record, 0), do: 0
  def undo(_record, cursor), do: cursor - 1

  @doc "Move the cursor one step forward, bounded by the record length."
  @impl true
  @spec redo(record(), cursor()) :: cursor()
  def redo(record, cursor) when cursor < length(record), do: cursor + 1
  def redo(_record, cursor), do: cursor

  @doc """
  Replay the history up to the current cursor to build the effective state.
  This is the core functional fold (reduce) that powers the compiler.
  """
  @impl true
  def resolve(record, cursor, base_graph) do
    {resolved_graph, data_state} =
      record
      |> Enum.take(cursor)
      |> Enum.reduce(
        {base_graph, %{inputs: %{}, overrides: %{}, offsets: %{}}},
        fn operation, {graph, state} ->
          apply_operation(operation, graph, state)
        end
      )

    %{resolved_graph: resolved_graph, data_state: data_state}
  end

  defp apply_operation({:override, %Edge{} = edge, data}, graph, state),
    do: {graph, put_in(state, [:overrides, edge], data)}

  defp apply_operation({:offset, %Edge{} = edge, offset_data}, graph, state),
    do: {graph, put_in(state, [:offsets, edge], offset_data)}

  defp apply_operation({:undo_modify, %Edge{} = edge}, graph, state),
    do:
      {graph,
       state
       |> update_in([:overrides], &Map.delete(&1, edge))
       |> update_in([:offsets], &Map.delete(&1, edge))}

  defp apply_operation({:set_input, {%Node{}, idx} = loc, data}, graph, state) when idx >= 0,
    do: {graph, put_in(state, [:inputs, loc], data)}

  defp apply_operation({:add_node, %Node{} = node}, graph, state) do
    new_nodes = if node in graph.nodes, do: graph.nodes, else: [node | graph.nodes]
    {%{graph | nodes: new_nodes}, state}
  end

  defp apply_operation({:remove_node, %Node{} = node}, graph, state) do
    new_nodes = Enum.reject(graph.nodes, &(&1.name == node.name))

    new_edges =
      Enum.reject(graph.edges, fn e ->
        e.from_node == node.name || e.to_node == node.name
      end)

    {%{graph | nodes: new_nodes, edges: new_edges}, state}
  end

  defp apply_operation({:add_edge, %Edge{} = edge}, graph, state) do
    new_edges = if edge in graph.edges, do: graph.edges, else: [edge | graph.edges]
    {%{graph | edges: new_edges}, state}
  end

  defp apply_operation({:remove_edge, %Edge{} = edge}, graph, state) do
    new_edges = Enum.reject(graph.edges, &(&1 == edge))
    {%{graph | edges: new_edges}, state}
  end

  defp apply_operation(_op, graph, state), do: {graph, state}
end
