defmodule OrchidPlugin.Cache do
  @moduledoc "Integrate OrchidStratum and OrchidInterventions."
  alias Quincunx.Session.Storage

  @behaviour OrchidPlugin

  @impl true
  @spec apply_plugin(OrchidPlugin.orchid_tuple(), nil | Quincunx.Session.Storage.t()) ::
          OrchidPlugin.orchid_tuple()
  def apply_plugin({recipe, base_run_opts}, context) do
    case context do
      %Storage{meta_conf: meta, blob_conf: blob} ->
        OrchidStratum.apply_cache(recipe, meta, blob, base_run_opts)
        |> apply_intervention_cache(nil, nil)

      _ ->
        {recipe, base_run_opts}
    end
    |> regist_hook_and_operons()
  end

  defp apply_intervention_cache({recipe, base_run_opts}, _interv, _merge) do
    {recipe, base_run_opts}
  end

  defp regist_hook_and_operons({recipe, base_run_opts}) do
    {hook_stack, old_opts} =
      Keyword.pop(base_run_opts, :global_hooks_stack, [])

    {new_operon, clean_opts} =
      Keyword.pop(old_opts, :operons_stack, [])

    final_opts =
      clean_opts ++
        [
          global_hooks_stack:
            [Orchid.Hook.ApplyInterventions, OrchidStratum.BypassHook] ++
              Enum.reject(hook_stack, fn module -> module == OrchidStratum.BypassHook end),
          operons_stack: [Orchid.Operon.ApplyInputs] ++ new_operon
        ]

    {recipe, final_opts}
  end
end
