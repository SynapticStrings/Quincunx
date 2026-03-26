defmodule OrchidPlugin.Instrument do
  @moduledoc """
  Integrate OrchidSymbiont with multiple Sessions.

  ### Usage

  Build several symionts and its related step.

      {OrchidPlugin.Instrument, {"CurrentSessionID", %{}}
  """

  @behaviour Orchid.Plugin

  @impl true
  def apply_plugin({orchid_recipe, opts}, symbionts_ctx)
      when not is_nil(symbionts_ctx) do
    {orchid_recipe, add_options(opts, symbionts_ctx)}
  end

  def apply_plugin({orchid_recipe, opts}, _nil) do
    {orchid_recipe, opts}
  end

  defp add_options(old_orchid_opts, {session_id, symbiont_mapper}) do
    {old_hooks_stack, old_orchid_opts_without_hooks} =
      Keyword.pop(old_orchid_opts, :global_hooks_stack, [])

    {old_baggage, clean_orchid_opts} = Keyword.pop(old_orchid_opts_without_hooks, :baggage, %{})

    clean_orchid_opts ++
      [
        baggage: Map.merge(old_baggage, %{symbiont_mapper: symbiont_mapper, scope_id: session_id}),
        global_hooks_stack: old_hooks_stack ++ [OrchidSymbiont.Hooks.Injector]
      ]
  end
end
