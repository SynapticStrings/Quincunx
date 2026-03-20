defmodule Quincunx.Lily.RecipeBundle do
  @moduledoc "It is a container to store some data that orchid or task runner required."

  alias Quincunx.Lily.Graph.{Node, Portkey}

  @type intervention(key) :: %{key => nil | %{Portkey.t() => any()}}

  @type t :: %__MODULE__{
          recipe: Orchid.Recipe.t(),
          requires: [Portkey.t()],
          exports: [Portkey.t()],
          node_ids: [Node.id()],
          inputs: nil | %{Portkey.t() => any()},
          overrides: nil | %{Portkey.t() => any()},
          offsets: nil | %{Portkey.t() => any()}
        }
  defstruct [:recipe, :requires, :exports, :node_ids, :inputs, :overrides, :offsets]
end
