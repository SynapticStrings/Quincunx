defmodule Quincunx.Segment.LinearRecorder do
  alias Quincunx.Segment.RecorderAdapter
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
  def push(record, cursor, operation), do:
    {Enum.take(record, cursor) ++ [operation], cursor + 1}

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
  def resolve(record, cursor, _base_graph) do
    Enum.take(record, cursor)
    |> Enum.reduce(
      %{inputs: %{}, overrides: %{}, offsets: %{}},
      fn operation, state ->
        apply_operation(operation, state)
      end
    )
  end

  defp apply_operation(_op, state), do: state

  # defp apply_operation({:set_input, port, value}, state) do
  #   put_in(state, [:inputs, port], value)
  # end

  # defp apply_operation({:override, node_id, port, ref}, state) do
  #   put_in(state, [:overrides, {node_id, port}], ref)
  # end

  # defp apply_operation({:remove_override, node_id, port}, state) do
  #   {_, new_overrides} = Map.pop(state.overrides, {node_id, port})
  #   %{state | overrides: new_overrides}
  # end

  # defp apply_operation({:offset, node_id, port, offset_data}, state) do
  #   update_in(state, [:offsets, {node_id, port}], fn existing ->
  #     (existing || []) ++ [offset_data]
  #   end)
  # end
end
