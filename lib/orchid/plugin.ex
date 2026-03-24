defmodule Orchid.Plugin do
  @moduledoc """
  Responsible to integrate Orchid's custome Hooks/Operons into Quincunx renderer.
  """

  @type orchid_tuple :: {Orchid.Recipe.t(), orchid_opts :: keyword()}

  @callback apply_plugin(orchid_tuple(), plugin_context :: term()) ::
              orchid_tuple()
end
