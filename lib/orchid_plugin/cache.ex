defmodule OrchidPlugin.Cache do
  @moduledoc "Integrate OrchidStratum."
  alias Quincunx.Session.Storage

  @behaviour Orchid.Plugin

  @impl true
  def scope_name, do: :storage_ctx

  @impl true
  @spec apply_plugin(Orchid.Plugin.orchid_tuple(), %{
          :storage_ctx => nil | Quincunx.Session.Storage.t()
        }) :: Orchid.Plugin.orchid_tuple()
  def apply_plugin({recipe, base_run_opts}, context) do
    case context do
      %{storage_ctx: %Storage{meta_conf: meta, blob_conf: blob}} ->
        OrchidStratum.apply_cache(recipe, meta, blob, base_run_opts)

      _ ->
        {recipe, base_run_opts}
    end
  end
end
