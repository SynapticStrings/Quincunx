defmodule OrchidPlugin.Cache do
  alias Quincunx.Session.Storage

  @behaviour Orchid.Plugin

  @impl true
  def apply_plugin({recipe, base_run_opts}, storage_ctx) do
    with %Storage{meta_conf: meta, blob_conf: blob} <- storage_ctx do
      OrchidStratum.apply_cache(recipe, meta, blob, base_run_opts)
    else
      nil ->
        {recipe, base_run_opts}
    end
  end
end
