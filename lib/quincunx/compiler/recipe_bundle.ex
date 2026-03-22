defmodule Quincunx.Compiler.RecipeBundle do
  @moduledoc "Container for static AST and dynamic parameters."

  alias Quincunx.Topology.Graph
  alias Quincunx.Editor.Segment

  @type intervention_type :: atom()
  @type port_interventions :: %{intervention_type() => any()}

  @type t :: %__MODULE__{
          id: Segment.id(),
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
end
