defmodule Quincunx.Compiler.RecipeBundle do
  @moduledoc "Container for static AST and dynamic parameters."

  alias Quincunx.Topology.Graph
  alias Quincunx.Editor.Segment

  @type t :: %__MODULE__{
          id: Segment.id(),
          recipe: Orchid.Recipe.t(),
          requires: [Orchid.Step.io_key()],
          exports: [Orchid.Step.io_key()],
          node_ids: [Graph.Node.id()],
          interventions: Segment.interventions_map()
        }
  defstruct [
    :id,
    :recipe,
    :requires,
    :exports,
    :node_ids,
    interventions: %{}
  ]

  # @spec get_intervention(t(), Graph.PortRef.t(), History.Operation.intervention_type()) :: any()
  # def get_intervention(%__MODULE__{} = bundle, port_ref, type) do
  #   get_in(bundle.interventions, [port_ref, type])
  # end

  # @spec put_intervention(t(), Graph.PortRef.t(), History.Operation.intervention_type(), any()) :: t()
  # def put_intervention(%__MODULE__{} = bundle, port_ref, type, value) do
  #   new_interventions =
  #     Map.update(bundle.interventions, port_ref, {type, value}, fn _old ->
  #       {type, value}
  #     end)

  #   %{bundle | interventions: new_interventions}
  # end

  @doc "Bind pure data interventions into given static recipe bundles."
  @spec bind_interventions([t()], Segment.interventions_map()) :: [t()]
  def bind_interventions(static_recipes, interventions_map) do
    do_bind_interventions(static_recipes, interventions_map)
  end

  @spec bind_interventions([t()], Segment.interventions_map(), Segment.interventions_map()) :: [
          t()
        ]
  def bind_interventions(static_recipes, interventions_map, interventions_from_segment) do
    Map.merge(interventions_map, interventions_from_segment)
    |> then(&do_bind_interventions(static_recipes, &1))
  end

  defp do_bind_interventions(static_recipes, interventions_map) do
    Enum.map(static_recipes, fn %{node_ids: node_ids} = static_bundle ->
      # Filter all interventions that belong to the current cluster nodes
      filtered_interventions =
        Map.filter(interventions_map, fn {{:port, target_node, _}, _port_data} ->
          target_node in node_ids
        end)

      %{static_bundle | interventions: filtered_interventions}
    end)
  end
end
