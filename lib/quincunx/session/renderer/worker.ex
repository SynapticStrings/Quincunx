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
    Enum.map(bundle.requires, fn orchid_key ->
      cond do
        Map.has_key?(blackboard.memory, {seg_id, orchid_key}) ->
          Map.fetch!(blackboard.memory, {seg_id, orchid_key})

        param = find_input_intervention(bundle.interventions, orchid_key) ->
          %{param | name: orchid_key}

        # Dangling inputs, use void
        true ->
          Orchid.Param.new(orchid_key, :void, nil)
      end
    end)
  end

  defp find_input_intervention(interventions, target_orchid_key) do
    # interventions's format:
    # %{{:port, id, name} => %{input: data, override: data}
    Enum.find_value(interventions, fn {port_ref, port_data} ->
      if PortRef.to_orchid_key(port_ref) == target_orchid_key do
        case Map.get(port_data, :input) do
          %Orchid.Param{} = param ->
            param

          raw_value when not is_nil(raw_value) ->
            Orchid.Param.new(target_orchid_key, :any, raw_value)

          _ ->
            nil
        end
      else
        false
      end
    end)
  end
end
