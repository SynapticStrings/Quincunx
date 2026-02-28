defmodule Quincunx.Session.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Quincunx.Session.Segment.History.Operation
  alias Quincunx.Session.Segment.{Graph, History, Compiler, Graph.Cluster}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          graph_with_cluster: {Graph.t(), Cluster.t()},
          compiled_recipes: nil | [Compiler.recipe_with_bundle()],
          history: History.t(),
          snapshots: %{optional(atom()) => any()},
          extra: map()
        }

  defstruct [
    :id,
    graph_with_cluster: {%Graph{}, %Cluster{}},
    compiled_recipes: nil,
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
          {:ok, Compiler.recipe_with_bundle() | [t()]} | {:error, term()}
  def compile_to_recipes(%__MODULE__{} = segment) do
    case compile_to_recipes([segment]) do
      {:ok, [compiled_seg]} -> {:ok, compiled_seg.compiled_recipes}
      {:error, _} = err -> err
    end
  end

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
    # %{{graph, cluster}, [%{segment: seg, interventions: interventions}]}
    |> Enum.reduce_while({:ok, []}, fn {{graph, cluster}, items}, {:ok, acc} ->
      case Compiler.compile(graph, cluster) do
        {:ok, static_recipes} ->
          compiled_group =
            Enum.map(items, fn item ->
              bound_recipes =
                static_recipes
                |> List.wrap()
                |> Compiler.bind_interventions(item.interventions)

              %{item.segment | compiled_recipes: bound_recipes}
            end)

          {:cont, {:ok, acc ++ compiled_group}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
