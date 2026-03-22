defmodule Quincunx.Renderer.Worker do
  @moduledoc """
  Translates and executes a single Recipe in isolation.
  Designed to be run as an asynchronous Task.
  """
  alias Quincunx.Topology.Graph.PortRef
  alias Quincunx.Session.Storage
  alias Quincunx.Editor.Segment
  alias Quincunx.Compiler.RecipeBundle
  alias Quincunx.Renderer.Blackboard

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

    base_baggage =
      for {k, v} <- orchid_custom_baggage,
          into: %{segments_id: seg_id},
          do: {k, v}

    base_run_opts = [
      executor_and_opts: orchid_executor_and_opts,
      baggage: base_baggage
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
    interventions_by_key =
      Map.new(bundle.interventions, fn {k, v} -> {PortRef.to_orchid_key(k), v} end)

    # Orchid accepts a bare list and can resolve via `param.name`
    # See Orchid.Scheduler.build/3
    Enum.map(bundle.requires, fn orchid_key ->
      cond do
        Map.has_key?(blackboard.memory, {seg_id, orchid_key}) ->
          Map.fetch!(blackboard.memory, {seg_id, orchid_key})

        port_data = Map.get(interventions_by_key, orchid_key) ->
          case Map.get(port_data, :input) do
            %Orchid.Param{} = param -> %{param | name: orchid_key}
            raw_value when not is_nil(raw_value) -> Orchid.Param.new(orchid_key, :any, raw_value)
            _ -> Orchid.Param.new(orchid_key, :void, nil)
          end

        # Dangling inputs, use void
        true ->
          Orchid.Param.new(orchid_key, :void, nil)
      end
    end)
  end
end
