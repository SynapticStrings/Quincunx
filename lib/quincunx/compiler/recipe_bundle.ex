defmodule Quincunx.Compiler.RecipeBundle do
  @moduledoc "Container for static AST and dynamic parameters."

  alias Quincunx.Topology.Graph
  alias Quincunx.Editor

  @type intervention_type :: atom()
  @type port_interventions :: %{intervention_type() => any()}

  @type t :: %__MODULE__{
          id: Editor.Segment.id(),
          recipe: Orchid.Recipe.t(),
          requires: [Orchid.Step.io_key()],
          exports: [Orchid.Step.io_key()],
          node_ids: [Graph.Node.id()],
          interventions: %{Graph.PortRef.t() => port_interventions()}
        }
  defstruct [
    :id,
    :recipe,
    :requires,
    :exports,
    :node_ids,
    interventions: %{}
  ]

  @spec get_intervention(t(), Graph.PortRef.t(), intervention_type()) :: any()
  def get_intervention(%__MODULE__{} = bundle, port_ref, type) do
    get_in(bundle.interventions, [port_ref, type])
  end

  @spec put_intervention(t(), Graph.PortRef.t(), intervention_type(), any()) :: t()
  def put_intervention(%__MODULE__{} = bundle, port_ref, type, value) do
    new_interventions =
      Map.update(bundle.interventions, port_ref, %{type => value}, fn port_data ->
        Map.put(port_data, type, value)
      end)

    %{bundle | interventions: new_interventions}
  end

  @doc "Bind pure data interventions into given static recipe bundles."
  @spec bind_interventions([t()], Editor.History.interventions_map()) :: [t()]
  def bind_interventions(static_recipes, interventions_map) do
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
