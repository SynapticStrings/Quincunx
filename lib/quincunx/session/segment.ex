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

  @spec compile_to_recipes(t() | [t()]) :: {:error, :cycle_detected} | {:ok, [map()]}
  def compile_to_recipes(%__MODULE__{} = segment) do
    {graph, cluster_declara} = segment.graph_with_cluster

    {final_graph, interventions} =
      History.resolve(graph, segment.history)

    final_graph
    |> Compiler.compile(cluster_declara)
    |> case do
      {:ok, recipe} ->
        recipe
        |> List.wrap()
        |> Compiler.bind_interventions(interventions)

      err ->
        err
    end
  end

  def compile_to_recipes(segments) when is_list(segments) do
    resolved_items =
      Enum.map(segments, fn segment ->
        {base_graph, cluster} = segment.graph_with_cluster
        {final_graph, interventions} = History.resolve(base_graph, segment.history)
        {{final_graph, cluster}, interventions}
      end)

    # Key: {final_graph, cluster}
    # Value: List of interventions
    grouped = Enum.group_by(resolved_items, &elem(&1, 0), &elem(&1, 1))

    Enum.reduce_while(grouped, {:ok, []}, fn {{graph, cluster}, interventions_list},
                                             {:ok, acc_recipes} ->
      case Compiler.compile(graph, cluster) do
        {:ok, recipe} ->
          bind_result =
            Enum.reduce(interventions_list, [], fn interventions, sub_acc ->
              sub_acc ++
                (recipe
                 |> List.wrap()
                 |> Compiler.bind_interventions(interventions))
            end)

          {:cont, {:ok, acc_recipes ++ bind_result}}

        err ->
          {:halt, err}
      end
    end)
  end
end
