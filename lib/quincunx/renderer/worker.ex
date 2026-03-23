defmodule Quincunx.Renderer.Worker do
  @moduledoc """
  Translates and executes a single Recipe in isolation.
  Designed to be run as an asynchronous Task.
  """
  alias Quincunx.Topology.Graph.PortRef
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
          map(),
          Enumerable.t(),
          keyword()
        ) ::
          {:ok, Segment.id(), map()} | {:error, term()}
  def run(
        seg_id,
        %RecipeBundle{} = bundle,
        blackboard,
        features,
        orchid_custom_baggage,
        orchid_opts
      ) do
    orchid_run_opts =
      build_orchid_opts(seg_id, bundle, blackboard, features, orchid_custom_baggage, orchid_opts)

    case apply(Orchid, :run, orchid_run_opts) do
      {:ok, results} ->
        {:ok, seg_id, results}

      {:error, reason} ->
        {:error, {:orchid_run_failed, seg_id, reason}}
    end
  end

  defp build_orchid_opts(
         seg_id,
         %RecipeBundle{} = bundle,
         blackboard,
         features,
         orchid_custom_baggage,
         orchid_opts
       ) do
    dynamic_inputs = resolve_dependencies(seg_id, bundle, blackboard)

    base_baggage =
      Enum.into(orchid_custom_baggage, %{})
      |> Map.put(:segments_id, seg_id)

    {recipe_to_run, final_run_opts} =
      OrchidPlugin.Cache.apply_plugin(
        {bundle.recipe, Keyword.merge([baggage: base_baggage], orchid_opts)},
        features
      )

    [recipe_to_run, dynamic_inputs, final_run_opts]
  end

  defp resolve_dependencies(
         seg_id,
         %RecipeBundle{requires: requires, interventions: interventions},
         %Blackboard{memory: blackboard}
       ) do
    # Orchid accepts a bare list and can resolve via `param.name`
    # See Orchid.Scheduler.build/3
    Enum.map(requires, fn orchid_key ->
      cond do
        Map.has_key?(blackboard, {seg_id, orchid_key}) ->
          Map.fetch!(blackboard, {seg_id, orchid_key})

        port_data =
            Map.new(interventions, fn {k, v} -> {PortRef.to_orchid_key(k), v} end)
            |> Map.get(orchid_key) ->
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
