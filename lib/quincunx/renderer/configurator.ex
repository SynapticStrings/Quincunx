defmodule Quincunx.Renderer.Configurator do
  @moduledoc """
  Immutable render-pass configuration.

  Built once at the dispatch boundary, threaded downward to Worker and the
  plugin chain. Adding a new `OrchidPlugin` never requires editing
  Dispatcher or Worker — just append it to `:plugins` and supply its
  scope key in opts.

  ## Options

    * `:plugins`        – ordered list of `{plugin, context}` tuples
    * `:orchid_baggage` – keyword/map merged into every Orchid run's baggage
    * `:orchid_opts`    – extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency`    – max parallel workers per stage
    * `:timeout`        – per-worker timeout
    * any key matching a plugin's `scope_name/0` is collected automatically
  """

  @type t :: %__MODULE__{
          plugins: [{module(), context :: any()}],
          orchid_baggage: map(),
          orchid_opts: keyword(),
          concurrency: pos_integer(),
          timeout: timeout()
        }

  defstruct plugins: [],
            orchid_baggage: %{},
            orchid_opts: [],
            concurrency: System.schedulers_online(),
            timeout: :infinity

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    plugins = Keyword.get(opts, :plugins, [])

    %__MODULE__{
      plugins: plugins,
      orchid_baggage: opts |> Keyword.get(:orchid_baggage, []) |> Enum.into(%{}),
      orchid_opts: Keyword.get(opts, :orchid_opts, []),
      concurrency: Keyword.get(opts, :concurrency, System.schedulers_online()),
      timeout: Keyword.get(opts, :timeout, :infinity)
    }
  end

  @doc """
  Run every plugin in order over the `{recipe, run_opts}` tuple.
  Each plugin may rewrite the recipe or append to run_opts.
  """
  @spec apply_plugins(t(), OrchidPlugin.orchid_tuple()) :: OrchidPlugin.orchid_tuple()
  def apply_plugins(%__MODULE__{plugins: plugins}, orchid_tuple) do
    Enum.reduce(plugins, orchid_tuple, fn plugin, acc ->
      case plugin do
        {plugin_module, context} when is_atom(plugin_module) ->
          plugin_module.apply_plugin(acc, context)

        plugin_module when is_atom(plugin_module) ->
          plugin_module.apply_plugin(acc, nil)
      end
    end)
  end
end
