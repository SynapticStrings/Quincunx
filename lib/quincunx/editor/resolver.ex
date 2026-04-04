defmodule Quincunx.Editor.History.Resolver do
  @moduledoc """
  Collapse the event sourcing history onto the base graph.
  Separates pure structural changes from data interventions for performance optimizations.
  """
  alias Quincunx.Topology.Graph
  alias Quincunx.Editor.{History, History.Operation}

  @type effective_state :: {
          Graph.t(),
          %{Graph.PortRef.t() => {Operation.intervention_type(), any()}}
        }

  @doc """
  Overlay all historical records onto the `base_graph` in chronological order.

  Output the valid states that the Compiler and Orchid need.
  """
  @spec resolve(History.t(), Graph.t()) :: effective_state()
  def resolve(%History{} = history, graph) do
    {topology_ops, data_ops} =
      history.undo_stack
      |> Enum.reverse()
      |> Enum.flat_map(&List.wrap/1) 
      |> Enum.split_with(&Operation.topology?/1)

    effective_graph = apply_topology(graph, topology_ops)
    interventions = apply_interventions(data_ops)

    {effective_graph, interventions}
  end

  defp apply_topology(%Graph{} = base_graph, topology_ops) do
    topology_ops
    |> Enum.reverse()
    |> Enum.reduce(base_graph, &do_apply_topology/2)
  end

  defp do_apply_topology({:add_node, node}, graph), do: Graph.add_node(graph, node)

  defp do_apply_topology({:update_node, node_id, new_node}, graph),
    do: Graph.update_node(graph, node_id, new_node)

  defp do_apply_topology({:remove_node, node_id}, graph), do: Graph.remove_node(graph, node_id)

  defp do_apply_topology({:add_edge, edge}, graph), do: Graph.add_edge(graph, edge)

  defp do_apply_topology({:remove_edge, edge}, graph), do: Graph.remove_edge(graph, edge)

  defp apply_interventions(data_ops) do
    data_ops
    |> Enum.reverse()
    |> Enum.reduce(%{}, &do_apply_intervention/2)
  end

  defp do_apply_intervention({:set_intervention, port_ref, type, value}, acc) do
    Map.update(acc, port_ref, {type, value}, fn _old -> {type, value} end)
  end

  defp do_apply_intervention({:clear_intervention, port_ref}, acc) do
    Map.delete(acc, port_ref)
  end
end
