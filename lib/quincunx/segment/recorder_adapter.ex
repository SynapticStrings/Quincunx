defmodule Quincunx.Segment.RecorderAdapter do
  @moduledoc """
  ...
  """

  @type operation :: any()
  @type record :: [operation()] | %{}
  @type cursor :: any()

  # op
  # record, cursor, op, op_context(e.g. new_param) =>
  # new_record, new_cursor

  # @callback apply_op(Quincunx.Segment.t())

  # current
  # record, cursor => current
end
