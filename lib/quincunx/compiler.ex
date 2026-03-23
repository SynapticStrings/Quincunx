defmodule Quincunx.Compiler do
  @moduledoc """
  The final stage of pure functional pipelines.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Quincunx.Editor.{History, Segment}
  alias Quincunx.Compiler.RecipeBundle

  @doc "Compile segments into batch-ready segments with attached recipe_bundles."
  @spec compile_to_recipes([Segment.t()]) ::
          {:ok, [{Segment.id(), [RecipeBundle.t()]}]} | {:error, term()}
  def compile_to_recipes(%Segment{} = segment), do: compile_to_recipes([segment])

  def compile_to_recipes(segments) when is_list(segments) do
    resolved_items =
      Enum.map(segments, fn seg ->
        %{graph: effective_graph, interventions: interventions} =
          History.Resolver.resolve(seg.history, seg.graph)

        %{segment: seg, graph: effective_graph, interventions: interventions}
      end)

    grouped_by_topology = Enum.group_by(resolved_items, &{&1.graph, &1.segment.cluster})

    Enum.reduce_while(grouped_by_topology, {:ok, []}, fn {{graph, cluster}, items}, {:ok, acc} ->
      case Quincunx.Compiler.GraphBuilder.compile_graph(graph, cluster) do
        {:ok, static_recipes} ->
          compiled_pairs =
            Enum.map(items, fn item ->
              bundles = RecipeBundle.bind_interventions(static_recipes, item.interventions)
              {item.segment.id, bundles}
            end)

          {:cont, {:ok, compiled_pairs ++ acc}}

        {:error, _reason} = err ->
          {:halt, err}
      end
    end)
  end
end
