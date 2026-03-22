defmodule OrchidPlugin.Instrument do
  # Integrate OrchidSymbiont

  @behaviour Orchid.Plugin

  def apply_plugin(recipe_opts, _plugin_context) do
    recipe_opts
  end
end
