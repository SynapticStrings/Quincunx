defmodule Quincunx.Compiler do
  @moduledoc """
  The final stage of pure functional pipelines.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Quincunx.Topology.{Graph, Graph.Node, Graph.PortRef, Cluster}
  alias Quincunx.Editor.{History, Segment}
  alias Quincunx.Compiler.RecipeBundle

  @doc "Compile segments into batch-ready segments with attached recipe_bundles."
  @spec compile_to_recipes(Segment.t() | [Segment.t()]) :: {:ok, [Segment.t()]} | {:error, term()}
  def compile_to_recipes(%Segment{} = segment), do: compile_to_recipes([segment])

  @spec compile_to_recipes([Segment.t()]) ::
          {:ok, [{Segment.id(), [RecipeBundle.t()]}]} | {:error, term()}
  def compile_to_recipes(segments) when is_list(segments) do
    resolved_items =
      Enum.map(segments, fn seg ->
        {effective_graph, interventions} = History.resolve(seg.graph, seg.history)
        %{segment: seg, graph: effective_graph, interventions: interventions}
      end)

    grouped_by_topology = Enum.group_by(resolved_items, &{&1.graph, &1.segment.cluster})

    Enum.reduce_while(grouped_by_topology, {:ok, []}, fn {{graph, cluster}, items}, {:ok, acc} ->
      case compile_graph(graph, cluster) do
        {:ok, static_recipes} ->
          compiled_pairs =
            Enum.map(items, fn item ->
              bundles = bind_interventions(static_recipes, item.interventions)
              {item.segment.id, bundles}
            end)

          {:cont, {:ok, compiled_pairs ++ acc}}

        {:error, _reason} = err ->
          {:halt, err}
      end
    end)
  end

  @doc "Compile a pure structural graph into generic isolated static recipes."
  @spec compile_graph(Graph.t(), Cluster.t()) ::
          {:error, :cycle_detected} | {:ok, [RecipeBundle.t()]}
  def compile_graph(%Graph{} = graph, cluster_declara \\ %Cluster{}) do
    with {:ok, sorted_node_ids} <- Graph.topological_sort(graph) do
      node_colors = Cluster.paint_graph(sorted_node_ids, graph.edges, cluster_declara)

      static_recipes =
        sorted_node_ids
        |> Enum.group_by(&Map.get(node_colors, &1, :default_cluster))
        |> Enum.map(fn {cluster_name, node_ids_in_cluster} ->
          build_recipe(cluster_name, node_ids_in_cluster, graph)
        end)

      {:ok, static_recipes}
    end
  end

  @doc "Bind pure data interventions into given static recipe bundles."
  @spec bind_interventions([RecipeBundle.t()], History.interventions_map()) :: [RecipeBundle.t()]
  def bind_interventions(static_recipes, interventions_map) do
    Enum.map(static_recipes, fn %{node_ids: node_ids} = static_bundle ->
      # Filter all interventions that belong to the current cluster nodes
      filtered_interventions =
        Map.filter(interventions_map, fn {{:port, target_node, _}, _port_data} ->
          target_node in node_ids
        end)

      %{static_bundle | interventions: filtered_interventions}
    end)
  end

  # --- Private Builders ---

  defp build_recipe(cluster_name, node_ids, graph) do
    steps =
      node_ids
      |> Enum.map(&Map.fetch!(graph.nodes, &1))
      |> Enum.map(&node_to_step(&1, graph))

    {requires, exports} = calculate_boundaries(node_ids, graph)

    %RecipeBundle{
      recipe: Orchid.Recipe.new(steps, name: cluster_name),
      requires: requires,
      exports: exports,
      node_ids: node_ids
    }
  end

  defp node_to_step(%Node{} = node, graph) do
    in_edges = Graph.get_in_edges(graph, node.id)

    step_inputs =
      Enum.map(node.inputs, fn port_name ->
        case Enum.find(in_edges, &(&1.to_port == port_name)) do
          nil -> PortRef.to_orchid_key({:port, node.id, port_name})
          edge -> PortRef.to_orchid_key({:port, edge.from_node, edge.from_port})
        end
      end)

    step_outputs = Enum.map(node.outputs, fn p -> PortRef.to_orchid_key({:port, node.id, p}) end)

    {node.impl, step_inputs, step_outputs, node.opts}
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    external_edges =
      graph.edges
      |> Enum.reject(&(&1.from_node in cluster_nodes_set and &1.to_node in cluster_nodes_set))

    external_in = external_edges |> Enum.filter(&(&1.to_node in cluster_nodes_set))
    external_out = external_edges |> Enum.filter(&(&1.from_node in cluster_nodes_set))

    in_keys = Enum.map(external_in, &PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))
    out_keys = Enum.map(external_out, &PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))

    edges_by_to_node = Enum.group_by(graph.edges, & &1.to_node)
    edges_by_from_node = Enum.group_by(graph.edges, & &1.from_node)

    dangling_inputs =
      Enum.flat_map(node_ids_in_cluster, &get_dangling_port(&1, graph, :inputs, edges_by_to_node))

    dangling_outputs =
      Enum.flat_map(
        node_ids_in_cluster,
        &get_dangling_port(&1, graph, :outputs, edges_by_from_node)
      )

    requires = Enum.uniq(in_keys ++ dangling_inputs)
    exports = Enum.uniq(out_keys ++ dangling_outputs)

    {requires, exports}
  end

  defp get_dangling_port(current_node_id, graph, direction, edges_attached_to_node) do
    node = graph.nodes[current_node_id]
    edges = Map.get(edges_attached_to_node, current_node_id, [])

    ports = if direction == :outputs, do: node.outputs, else: node.inputs
    match_field = if direction == :outputs, do: :from_port, else: :to_port

    ports
    |> Enum.reject(fn port -> Enum.any?(edges, &(Map.get(&1, match_field) == port)) end)
    |> Enum.map(fn port -> PortRef.to_orchid_key({:port, node.id, port}) end)
  end
end
