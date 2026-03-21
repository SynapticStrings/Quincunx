defmodule Quincunx.Session.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Quincunx.Lily.History.Operation
  alias Quincunx.Lily.{Graph, History, Compiler, Graph.Cluster, RecipeBundle}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          graph_with_cluster: {Graph.t(), Cluster.t()},
          recipe_bundles: nil | [RecipeBundle.t()],
          history: History.t(),
          snapshots: %{optional(atom()) => any()},
          extra: map()
        }

  defstruct [
    :id,
    graph_with_cluster: {%Graph{}, %Cluster{}},
    recipe_bundles: nil,
    history: %History{},
    snapshots: %{},
    extra: %{}
  ]

  @spec new(id(), Graph.t()) :: t()
  @spec new(id(), Graph.t(), Cluster.t()) :: t()
  def new(id, graph, cluster_declara \\ %Cluster{}) do
    %__MODULE__{
      id: id,
      graph_with_cluster: {graph, cluster_declara},
      history: History.new()
    }
  end

  @spec apply_operation(t(), Operation.t()) :: t()
  def apply_operation(%__MODULE__{} = segment, operation) do
    %{segment | history: History.push(segment.history, operation)}
  end

  @spec undo(t()) :: t()
  def undo(%__MODULE__{} = segment) do
    %{segment | history: History.undo(segment.history)}
  end

  @spec redo(t()) :: t()
  def redo(%__MODULE__{} = segment) do
    %{segment | history: History.redo(segment.history)}
  end

  @spec compile_to_recipes([t()] | t()) ::
          {:ok, [t()]} | {:error, term()}
  def compile_to_recipes(%__MODULE__{} = segment), do: compile_to_recipes([segment])

  def compile_to_recipes(segments) when is_list(segments) do
    segments
    |> Enum.map(fn seg ->
      {base_graph, cluster} = seg.graph_with_cluster
      {final_graph, interventions} = History.resolve(base_graph, seg.history)

      %{
        segment: seg,
        group_key: {final_graph, cluster},
        interventions: interventions
      }
    end)
    |> Enum.group_by(& &1.group_key)
    |> Enum.reduce_while({:ok, []}, fn {group_key, items}, {:ok, acc} ->
      case merge_segments_per_graph(group_key, items) do
        {:ok, compiled_group} -> {:cont, {:ok, acc ++ compiled_group}}
        err -> {:halt, err}
      end
    end)
  end

  defp merge_segments_per_graph({graph, cluster}, segments_and_interventions) do
    case Compiler.compile_graph(graph, cluster) do
      {:ok, static_recipes} ->
        compiled_group =
          Enum.map(
            segments_and_interventions,
            fn %{
                 segment: seg,
                 interventions: interventions
               } ->
              %{
                seg
                | recipe_bundles:
                    static_recipes
                    |> List.wrap()
                    |> Compiler.bind_interventions(interventions)
              }
            end
          )

        {:ok, compiled_group}

      {:error, _reason} = err ->
        err
    end
  end
end
