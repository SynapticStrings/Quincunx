defmodule Orchid.Plugin do
  @type orchid_tuple :: {Orchid.Recipe.t(), orchid_opts :: keyword()}

  @type context_name :: atom()

  @callback scope_name() :: context_name()

  @callback apply_plugin(orchid_tuple(), %{context_name() => plugin_context :: term()}) ::
              orchid_tuple()
end
