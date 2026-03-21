defmodule Quincunx.Session.Renderer.Worker do
  @moduledoc """
  Translates and executes a single Recipe in isolation.
  Designed to be run as an asynchronous Task.
  """
  alias Quincunx.Lily.Graph.PortRef
  alias Quincunx.Session.{Storage, Segment}
  alias Quincunx.Lily.RecipeBundle
  alias Quincunx.Session.Renderer.Blackboard

  @doc """
  Executes the recipe and returns the output port data.
  """
  @spec run(
          Segment.id(),
          RecipeBundle.t(),
          Blackboard.t(),
          Storage.t() | nil,
          {module(), keyword()},
          Enumerable.t(),
          term()
        ) ::
          {:ok, Segment.id(), map()} | {:error, term()}
  def run(
        seg_id,
        %RecipeBundle{} = bundle,
        blackboard,
        storage_ctx,
        orchid_executor_and_opts \\ {Orchid.Executor.Serial, []},
        orchid_custom_baggage \\ [],
        _orchid_restart_opts \\ nil
      ) do
    dynamic_inputs = resolve_dependencies(seg_id, bundle, blackboard)

    # TODO: merge static interventions

    base_run_opts = [
      executor_and_opts: orchid_executor_and_opts,
      baggage: [segment_id: seg_id] ++ orchid_custom_baggage
    ]

    {recipe_to_run, final_run_opts} =
      case storage_ctx do
        %Storage{meta_conf: meta, blob_conf: blob} ->
          OrchidStratum.apply_cache(bundle.recipe, meta, blob, base_run_opts)

        nil ->
          {bundle.recipe, base_run_opts}
      end

    case Orchid.run(recipe_to_run, dynamic_inputs, final_run_opts) do
      {:ok, results} ->
        {:ok, seg_id, results}

      {:error, reason} ->
        {:error, {:orchid_run_failed, seg_id, reason}}
    end
  end

  defp resolve_dependencies(seg_id, %RecipeBundle{} = bundle, %Blackboard{} = blackboard) do
    inputs_map = RecipeBundle.get_interventions(bundle, "inputs")

    Enum.map(bundle.requires, fn port_ref ->
      cond do
        # 1. Check Blackboard Memory first
        Map.has_key?(blackboard.memory, {seg_id, port_ref}) ->
          Map.get(blackboard.memory, {seg_id, port_ref})

        # 2. Check Interventions
        param = find_intervention_param(inputs_map, port_ref) ->
          %{param | name: port_ref}

        # 3. Fallback
        true ->
          Orchid.Param.new(port_ref, :void, nil)
      end
    end)
  end

  defp find_intervention_param(inputs_map, target_port_ref) when is_map(inputs_map) do
    Enum.find_value(inputs_map, fn {raw_k, _v} = param ->
      if PortRef.to_orchid_key(raw_k) == target_port_ref, do: param, else: false
    end)
    |> case do
      {_key, %Orchid.Param{} = raw_param} -> raw_param
      _ -> nil
    end
  end
end
