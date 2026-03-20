defmodule Quincunx.Lily.RecipeBundle do
  @moduledoc "It is a container to store some data that orchid or task runner required."

  alias Quincunx.Lily.Graph.{Node, Portkey}

  @type intervention :: nil | %{Portkey.t() => any()}

  @type interventions(key) :: %{key => intervention()}

  @type t :: %__MODULE__{
          recipe: Orchid.Recipe.t(),
          requires: [Portkey.t()],
          exports: [Portkey.t()],
          node_ids: [Node.id()],
          interventions: interventions(atom())
        }
  defstruct [
    :recipe,
    :requires,
    :exports,
    :node_ids,
    interventions: %{}
  ]

  @spec get_interventions(t(), atom()) :: map()
  def get_interventions(%__MODULE__{interventions: interventions}, key),
    do: Map.get(interventions, key, %{})

  def get_intervention(%__MODULE__{} = bundle, key, [port]),
    do: get_in(get_interventions(bundle, key), port)

  def put_interventions(%__MODULE__{interventions: interventions} = bundle, key, intervention),
    do: %{bundle | interventions: Map.put(interventions, key, intervention)}

  def put_intervention(%__MODULE__{} = bundle, key, [port], value),
    do: put_interventions(bundle, key, put_in(get_interventions(bundle, key), port, value))
end
