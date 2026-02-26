defmodule Quincunx.Session.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  It holds the static topology, user edit history, and cached runtime references.
  """

  alias Lily.History.Operation
  alias Lily.{Graph, History, Compiler, Graph.Cluster}

  @type id :: atom() | String.t()

  @type t :: %__MODULE__{
          id: id(),
          graph_with_cluster: {Graph.t(), Cluster.t()},
          history: History.t(),
          snapshots: %{optional(atom()) => any()},
          extra: map()
        }

  defstruct [
    :id,
    graph_with_cluster: {%Graph{}, %Cluster{}},
    history: %History{},
    snapshots: %{},
    extra: %{}
  ]

  @spec new(id(), Graph.t()) :: t()
  @spec new(id(), Graph.t(), Cluster.t()) :: t()
  def new(id, graph_with_cluster, cluster_declara \\ %Cluster{}) do
    %__MODULE__{
      id: id,
      graph_with_cluster: {graph_with_cluster, cluster_declara},
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

  @spec compile_batch([t()]) :: {:error, :cycle_detected} | {:ok, [%{id() => any()}]}
  def compile_batch(segments) do
    Enum.map(segments, fn seg ->
      {graph, cluster} = seg.graph_with_cluster
      {final_graph, interventions} = History.resolve(graph, seg.history)

      %{
        id: seg.id,
        key: {final_graph, cluster},
        interventions: interventions
      }
    end)
    |> Enum.group_by(& &1.key)
    |> Enum.reduce_while({:ok, []}, fn {{graph, cluster}, items}, {:ok, acc} ->
      case Compiler.compile(graph, cluster) do
        {:ok, base_recipes} ->
          # base_recipes 是一个列表 [Recipe_Stage1, Recipe_Stage2, ...]
          # 我们需要为组内的每个 item 生成一份绑定后的 recipe 列表
          bound_group =
            Enum.map(items, fn item ->
              bound_recipes = Compiler.bind_interventions(base_recipes, item.interventions)
              {item.id, bound_recipes}
            end)

          {:cont, {:ok, acc ++ bound_group}}

        error ->
          {:halt, error}
      end
    end)
  end
end
