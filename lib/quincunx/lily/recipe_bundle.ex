defmodule Quincunx.Lily.RecipeBundle do
  @moduledoc "It is a container to store some data that orchid or task runner required."

  alias Quincunx.Lily.Graph.{Node, Portkey}

  @type intervention :: %{} | %{Portkey.t() => any()}
  @type intervention_name :: atom()
  @type interventions(key) :: %{key => intervention()}

  @type t :: %__MODULE__{
          recipe: Orchid.Recipe.t(),
          requires: [Portkey.t()],
          exports: [Portkey.t()],
          node_ids: [Node.id()],
          interventions: interventions(intervention_name())
        }
  defstruct [
    :recipe,
    :requires,
    :exports,
    :node_ids,
    interventions: %{}
  ]

  @spec get_interventions(t(), intervention_name()) :: map()
  def get_interventions(%__MODULE__{interventions: interventions}, key),
    do: Map.get(interventions, key, %{})

  @spec get_intervention(t(), intervention_name(), Portkey.t()) :: any()
  def get_intervention(%__MODULE__{} = bundle, key, port),
    do: get_in(bundle.interventions, [key, port])

  @spec put_interventions(t(), intervention_name(), intervention()) :: t()
  def put_interventions(%__MODULE__{interventions: interventions} = bundle, key, intervention),
    do: %{bundle | interventions: Map.put(interventions, key, intervention)}

  @spec put_intervention(t(), atom(), Portkey.t(), any()) ::t()
  def put_intervention(%__MODULE__{} = bundle, key, port, value),
    do: put_interventions(bundle, key, put_in(bundle.interventions, [key, port], value))
end
