defmodule Orchid.Plugin do
  @type orchid_tuple :: {Orchid.Recipe.t(), orchid_opts :: keyword()}
  @callback apply_plugin(orchid_tuple(), plugin_context :: term()) :: orchid_tuple()
end
