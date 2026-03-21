defmodule Quincunx.Lily.Compiler do
  @moduledoc """
  The final stage of pure functional pipelines.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Quincunx.Lily.{Graph, History, RecipeBundle}
  alias Quincunx.Lily.Graph.{Node, Portkey, Cluster}

  @spec compile_graph(Graph.t()) :: {:error, :cycle_detected} | {:ok, [RecipeBundle.t()]}
  def compile_graph(%Graph{} = graph, cluster_declara \\ %Cluster{}) do
    case Graph.topological_sort(graph) do
      {:error, _} = err ->
        err

      {:ok, sorted_node_ids} ->
        node_colors = Cluster.paint_graph(sorted_node_ids, graph.edges, cluster_declara)

        clusters = Enum.group_by(sorted_node_ids, &Map.get(node_colors, &1, :default_cluster))

        static_recipes =
          Enum.map(clusters, fn {cluster_name, node_ids_in_cluster} ->
            build_recipe(cluster_name, node_ids_in_cluster, graph)
          end)

        {:ok, static_recipes}
    end
  end

  @spec bind_interventions([RecipeBundle.t()], History.inputs_bundle()) :: [RecipeBundle.t()]
  def bind_interventions(static_recipes, inputs_bundles) do
    Enum.map(static_recipes, fn %{node_ids: node_ids} = static_bundle ->
      Enum.reduce(inputs_bundles, static_bundle, fn {key, data}, bundle_acc ->
        filtered_data = filter_port_data(data, node_ids)
        RecipeBundle.put_interventions(bundle_acc, key, filtered_data)
      end)
    end)
  end

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
          nil -> Portkey.to_orchid_key({:port, node.id, port_name})
          edge -> Portkey.to_orchid_key({:port, edge.from_node, edge.from_port})
        end
      end)

    step_outputs = Enum.map(node.outputs, fn p -> Portkey.to_orchid_key({:port, node.id, p}) end)

    build_orchid_step(node.impl, step_inputs, step_outputs, node.opts)
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    ## External Edges

    external_in_edges =
      graph.edges
      |> Enum.filter(&(&1.to_node in cluster_nodes_set and &1.from_node not in cluster_nodes_set))
      |> Enum.map(&Portkey.to_orchid_key({:port, &1.from_node, &1.from_port}))

    external_out_edges =
      graph.edges
      |> Enum.filter(&(&1.from_node in cluster_nodes_set and &1.to_node not in cluster_nodes_set))
      |> Enum.map(&Portkey.to_orchid_key({:port, &1.from_node, &1.from_port}))

    ## Dangling Edges

    edges_by_to_node = Enum.group_by(graph.edges, & &1.to_node)
    edges_by_from_node = Enum.group_by(graph.edges, & &1.from_node)

    dangling_inputs =
      Enum.flat_map(node_ids_in_cluster, fn node_id ->
        node = graph.nodes[node_id]

        in_edges = Map.get(edges_by_to_node, node_id, [])

        node.inputs
        |> Enum.reject(fn port -> Enum.any?(in_edges, &(&1.to_port == port)) end)
        |> Enum.map(fn port -> Portkey.to_orchid_key({:port, node.id, port}) end)
      end)

    requires = Enum.uniq(external_in_edges ++ dangling_inputs)

    # when REAL Outputs may
    dangling_outputs =
      Enum.flat_map(node_ids_in_cluster, fn node_id ->
        node = graph.nodes[node_id]

        out_edges = Map.get(edges_by_from_node, node_id, [])

        node.outputs
        |> Enum.reject(fn port -> Enum.any?(out_edges, &(&1.to_port == port)) end)
        |> Enum.map(fn port -> Portkey.to_orchid_key({:port, node.id, port}) end)
      end)

    exports = Enum.uniq(external_out_edges ++ dangling_outputs)

    {requires, exports}
  end

  defp filter_port_data(data_map, node_ids) do
    data_map
    |> Enum.filter(fn {{:port, target_node, _port}, _data} -> target_node in node_ids end)
    |> Enum.into(%{})
  end

  def build_orchid_step(impl, inputs, outputs, opts) do
    {impl, inputs, outputs, opts}
  end
end
