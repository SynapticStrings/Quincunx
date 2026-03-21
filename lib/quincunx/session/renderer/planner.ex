defmodule Quincunx.Session.Renderer.Planner do
  @moduledoc """
  Aligning `Quincunx.Session.Segment`s into pipeline batch.
  """
  alias Quincunx.Session.Segment
  alias Quincunx.Lily.RecipeBundle

  @type render_task :: {Segment.id(), RecipeBundle.t()}
  @type stage :: [render_task()]

  def build(segments) do
    with {:ok, compiled_recipes} <- Segment.compile_to_recipes(segments) do
      {:ok, compiled_recipes}
    else
      err -> err
    end
  end
end
