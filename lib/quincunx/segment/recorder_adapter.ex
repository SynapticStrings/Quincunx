defmodule Quincunx.Segment.RecorderAdapter do
  @moduledoc """
  Behavior for managing user edit history (Undo/Redo) and resolving
  the effective state (Inputs, Overrides, Offsets) for the compiler.
  """
  alias Quincunx.Dependency.{Node, Edge}

  @type operation ::
          {:override, source_edge :: Edge.t(), data :: any()}
          | {:offset, source_edge :: Edge.t(), offset_data :: any()}
          | {:undo_modify, source_edge :: Edge.t()}
          | {:add_node, Node.t()}
          | {:remove_node, Node.t()}
          | {:add_edge, Edge.t()}
          | {:remove_edge, Edge.t()}
          | {:set_input, port_id :: {Node.t(), idx :: non_neg_integer()}, value :: any()}

  @type record :: any()
  @type cursor :: any()

  @doc "final state from specific snapshot(init), operations(record) and cursor."
  @type effective_state :: %{
      resolved_graph: Quincunx.Dependency.t(),
      data_state: %{inputs: map(), overrides: map(), offsets: map()}
    }

  # TODO: {:ok, state} | {:error, reason}
  @callback push(record(), cursor(), operation() | [operation()] | %{any() => operation()}) :: {record(), cursor()}

  @callback undo(record(), cursor()) :: cursor()

  @callback redo(record(), cursor()) :: cursor()

  @callback resolve(record(), cursor(), base_graph :: Quincunx.Dependency.t()) :: effective_state()
end
