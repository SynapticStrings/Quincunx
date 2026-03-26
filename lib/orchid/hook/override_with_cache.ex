defmodule Orchid.Hook.OverrideWithCache do
  @moduledoc """
  ...

  ### Prerequisite and Order

  It requires raw data.
  """
  @behaviour Orchid.Runner.Hook

  @impl true
  def call(ctx, next_fn) do
    # When intervention at Input slot =>
    #   replace inputs, then call `OrchidStratum.BypassHook`
    #     explicitly;
    # When intercention at Output slot(FULL) =>
    #   replace outputs directly;
    ## When intercention at Output slot(PARTIAL) =>
    #   call inner function and then replace related output;
    OrchidStratum.BypassHook.call(ctx, next_fn)
  end

  def get_override(%Orchid.Runner.Context{workflow_ctx: workflow_ctx}) do
    Orchid.WorkflowCtx.get_baggage(workflow_ctx, :override, %{})
  end

  def get_offset(%Orchid.Runner.Context{workflow_ctx: workflow_ctx}) do
    Orchid.WorkflowCtx.get_baggage(workflow_ctx, :offset, %{})
  end
end
