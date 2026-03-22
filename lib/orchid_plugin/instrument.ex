defmodule OrchidPlugin.Instrument do
  # Integrate OrchidSymbiont

  @behaviour Orchid.Plugin

  @impl true
  def scope_name, do: :instrument

  @impl true
  def apply_plugin(recipe_opts, %{instrument: _context}) do
    recipe_opts
  end
end
