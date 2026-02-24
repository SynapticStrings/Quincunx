defmodule Orchid.Hook.Override do
  @moduledoc """
  ...

  ### Prerequisite and Order

  It requires raw data.
  """
  @behaviour Orchid.Runner.Hook

  @impl true
  def call(ctx, next_fn) do
    next_fn.(ctx)
  end

  def get_override(%Orchid.Runner.Context{workflow_ctx: workflow_ctx}) do
    Orchid.WorkflowCtx.get_baggage(workflow_ctx, :override, %{})
  end

  def get_offset(%Orchid.Runner.Context{workflow_ctx: workflow_ctx}) do
    Orchid.WorkflowCtx.get_baggage(workflow_ctx, :offset, %{})
  end
end
