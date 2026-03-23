defmodule Quincunx.Renderer.Context do
  @moduledoc """
  Immutable render-pass configuration.

  Built once at the dispatch boundary, threaded downward to Worker and the
  plugin chain. Adding a new `Orchid.Plugin` never requires editing
  Dispatcher or Worker — just append it to `:plugins` and supply its
  scope key in opts.

  ## Options

    * `:plugins`        – ordered list of `Orchid.Plugin` modules
    * `:orchid_baggage` – keyword/map merged into every Orchid run's baggage
    * `:orchid_opts`    – extra keyword opts forwarded to `Orchid.run/3`
    * `:concurrency`    – max parallel workers per stage
    * `:timeout`        – per-worker timeout
    * any key matching a plugin's `scope_name/0` is collected automatically
  """

  @type t :: %__MODULE__{
          plugins: [module()],
          scopes: %{atom() => term()},
          orchid_baggage: map(),
          orchid_opts: keyword(),
          concurrency: pos_integer(),
          timeout: timeout()
        }

  defstruct plugins: [],
            scopes: %{},
            orchid_baggage: %{},
            orchid_opts: [],
            concurrency: System.schedulers_online(),
            timeout: :infinity

  @default_plugins [OrchidPlugin.Cache, OrchidPlugin.Instrument]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    plugins = Keyword.get(opts, :plugins, @default_plugins)

    %__MODULE__{
      plugins: plugins,
      scopes: collect_scopes(plugins, opts),
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
  @spec apply_plugins(t(), Orchid.Plugin.orchid_tuple()) :: Orchid.Plugin.orchid_tuple()
  def apply_plugins(%__MODULE__{plugins: plugins, scopes: scopes}, orchid_tuple) do
    Enum.reduce(plugins, orchid_tuple, fn plugin, acc ->
      plugin.apply_plugin(acc, scopes)
    end)
  end

  # Automatically collects each plugin's scope_name from opts.
  defp collect_scopes(plugins, opts) do
    for plugin <- plugins, into: %{} do
      key = plugin.scope_name()
      {key, Keyword.get(opts, key)}
    end
  end
end
