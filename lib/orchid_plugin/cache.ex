defmodule OrchidPlugin.Cache do
  @moduledoc "Integrate OrchidStratum."
  alias Quincunx.Session.Storage

  @behaviour Orchid.Plugin

  @impl true
  @spec apply_plugin(Orchid.Plugin.orchid_tuple(), nil | Quincunx.Session.Storage.t()) ::
          Orchid.Plugin.orchid_tuple()
  def apply_plugin({recipe, base_run_opts}, context) do
    case context do
      %Storage{meta_conf: meta, blob_conf: blob} ->
        OrchidStratum.apply_cache(recipe, meta, blob, base_run_opts)

      _ ->
        {recipe, base_run_opts}
    end
    |> then(fn
      {recipe, old_opts} ->
        hook_stack =
          Keyword.get(old_opts, :global_hooks_stack)
          |> Enum.reject(fn module -> module == OrchidStratum.BypassHook end)

        # Use Orchid.Hook.OverrideWithCache to replace
        {recipe, [Orchid.Hook.OverrideWithCache | hook_stack]}
    end)
  end
end
