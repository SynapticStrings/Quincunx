defmodule Quincunx.Compiler do
  @moduledoc """
  The final stage of pure functional pipelines.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Quincunx.Topology.{Graph, Graph.Node, Graph.PortRef, Cluster}
  alias Quincunx.Editor.History
  alias Quincunx.Compiler.RecipeBundle

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

  @spec bind_interventions([RecipeBundle.t()], History.interventions_map()) :: [RecipeBundle.t()]
  def bind_interventions(static_recipes, interventions_map) do
    Enum.map(static_recipes, fn %{node_ids: node_ids} = static_bundle ->
      # filter all interventions that belongs to current cluster node
      filtered_interventions =
        Map.filter(interventions_map, fn {{:port, target_node, _}, _port_data} ->
          target_node in node_ids
        end)

      %{static_bundle | interventions: filtered_interventions}
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
          nil -> PortRef.to_orchid_key({:port, node.id, port_name})
          edge -> PortRef.to_orchid_key({:port, edge.from_node, edge.from_port})
        end
      end)

    step_outputs = Enum.map(node.outputs, fn p -> PortRef.to_orchid_key({:port, node.id, p}) end)

    build_orchid_step(node.impl, step_inputs, step_outputs, node.opts)
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    ## External Edges

    external_in_edges =
      graph.edges
      |> Enum.filter(&(&1.to_node in cluster_nodes_set and &1.from_node not in cluster_nodes_set))
      |> Enum.map(&PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))

    external_out_edges =
      graph.edges
      |> Enum.filter(&(&1.from_node in cluster_nodes_set and &1.to_node not in cluster_nodes_set))
      |> Enum.map(&PortRef.to_orchid_key({:port, &1.from_node, &1.from_port}))

    ## Dangling Edges

    edges_by_to_node = Enum.group_by(graph.edges, & &1.to_node)
    edges_by_from_node = Enum.group_by(graph.edges, & &1.from_node)

    dangling_inputs =
      Enum.flat_map(
        node_ids_in_cluster,
        &get_dangling_port(&1, graph, :inputs, edges_by_to_node)
      )

    dangling_outputs =
      Enum.flat_map(
        node_ids_in_cluster,
        &get_dangling_port(&1, graph, :outputs, edges_by_from_node)
      )

    ## Final Results

    requires = Enum.uniq(external_in_edges ++ dangling_inputs)

    exports = Enum.uniq(external_out_edges ++ dangling_outputs)

    {requires, exports}
  end

  defp get_dangling_port(current_node_id, graph, field, edges_attached_to_node) do
    node = graph.nodes[current_node_id]

    edges = Map.get(edges_attached_to_node, current_node_id, [])

    case field do
      :outputs ->
        node.outputs
        |> Enum.reject(fn port -> Enum.any?(edges, &(&1.from_port == port)) end)
        |> Enum.map(fn port -> PortRef.to_orchid_key({:port, node.id, port}) end)

      :inputs ->
        node.inputs
        |> Enum.reject(fn port -> Enum.any?(edges, &(&1.to_port == port)) end)
        |> Enum.map(fn port -> PortRef.to_orchid_key({:port, node.id, port}) end)
    end
  end

  def build_orchid_step(impl, inputs, outputs, opts) do
    {impl, inputs, outputs, opts}
  end
end
