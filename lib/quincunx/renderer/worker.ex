defmodule Quincunx.Renderer.Worker do
  @moduledoc """
  Executes a single RecipeBundle in isolation.

  Resolves dependencies from the Blackboard, applies the plugin pipeline
  via Configurator, then delegates to `Orchid.run/3`.
  """

  alias Quincunx.Topology.Graph.PortRef
  alias Quincunx.Editor.Segment
  alias Quincunx.Compiler.RecipeBundle
  alias Quincunx.Renderer.{Blackboard, Configurator}

  @spec run(Segment.id(), RecipeBundle.t(), Blackboard.t(), Configurator.t()) ::
          {:ok, Segment.id(), map()} | {:error, term()}
  def run(seg_id, %RecipeBundle{} = bundle, %Blackboard{} = blackboard, %Configurator{} = ctx) do
    dynamic_inputs = resolve_dependencies(seg_id, bundle, blackboard)

    baggage =
      ctx.orchid_baggage
      |> Map.put(:segments_id, seg_id)

    base_opts = Keyword.merge(ctx.orchid_opts, baggage: baggage)

    {recipe, final_opts} = Configurator.apply_plugins(ctx, {bundle.recipe, base_opts})

    case Orchid.run(recipe, dynamic_inputs, final_opts) do
      {:ok, results} -> {:ok, seg_id, results}
      {:error, reason} -> {:error, {:orchid_run_failed, seg_id, reason}}
    end
  end

  defp resolve_dependencies(seg_id, %RecipeBundle{} = bundle, %Blackboard{memory: mem}) do
    intervention_by_orchid_key =
      Map.new(bundle.interventions, fn {k, v} -> {PortRef.to_orchid_key(k), v} end)

    Enum.map(bundle.requires, fn orchid_key ->
      case Map.fetch(mem, {seg_id, orchid_key}) do
        {:ok, val} ->
          Orchid.Param.new(orchid_key, :any, val)

        :error ->
          resolve_from_intervention(orchid_key, intervention_by_orchid_key)
      end
    end)
  end

  defp resolve_from_intervention(orchid_key, interventions) do
    case Map.get(interventions, orchid_key) do
      %{input: %Orchid.Param{} = param} -> %{param | name: orchid_key}
      %{input: raw} when not is_nil(raw) -> Orchid.Param.new(orchid_key, :any, raw)
      _ -> Orchid.Param.new(orchid_key, :void, nil)
    end
  end
end
