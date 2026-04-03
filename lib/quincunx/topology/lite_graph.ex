defmodule Quincunx.Topology.LiteGraph do
  @moduledoc """
  Lightweight DAG for modelling dependencies between opaque identifiers.

  Shares the topological-sort algorithm pattern with `Quincunx.Topology.Graph`
  but carries no domain payload (no container, ports, etc.).

  Typical usage: inter-Segment ordering, group-level scheduling.
  """

  @type node_id :: term()

  @type edge :: {from :: node_id(), to :: node_id()}

  @type t :: %__MODULE__{
          nodes: MapSet.t(node_id()),
          edges: MapSet.t(edge()),
          in_adj: %{node_id() => [node_id()]},
          out_adj: %{node_id() => [node_id()]}
        }

  defstruct nodes: MapSet.new(),
            edges: MapSet.new(),
            in_adj: %{},
            out_adj: %{}

  def new, do: %__MODULE__{nodes: MapSet.new(), edges: MapSet.new(), in_adj: %{}, out_adj: %{}}

  def add_node(%__MODULE__{} = g, id) do
    %{
      g
      | nodes: MapSet.put(g.nodes, id),
        in_adj: Map.put_new(g.in_adj, id, []),
        out_adj: Map.put_new(g.out_adj, id, [])
    }
  end

  def remove_node(%__MODULE__{} = g, id) do
    in_neighbors = Map.get(g.in_adj, id, [])
    out_neighbors = Map.get(g.out_adj, id, [])

    edges_to_remove =
      Enum.map(in_neighbors, &{&1, id}) ++ Enum.map(out_neighbors, &{id, &1})

    new_edges = Enum.reduce(edges_to_remove, g.edges, &MapSet.delete(&2, &1))

    new_in_adj =
      Enum.reduce(out_neighbors, g.in_adj, fn neighbor, acc ->
        Map.update!(acc, neighbor, &List.delete(&1, id))
      end)
      |> Map.delete(id)

    new_out_adj =
      Enum.reduce(in_neighbors, g.out_adj, fn neighbor, acc ->
        Map.update!(acc, neighbor, &List.delete(&1, id))
      end)
      |> Map.delete(id)

    %{
      g
      | nodes: MapSet.delete(g.nodes, id),
        edges: new_edges,
        in_adj: new_in_adj,
        out_adj: new_out_adj
    }
  end

  def add_edge(%__MODULE__{} = g, from, to) do
    cond do
      from == to ->
        g

      MapSet.member?(g.edges, {from, to}) ->
        g

      true ->
        %{
          g
          | edges: MapSet.put(g.edges, {from, to}),
            out_adj: Map.update(g.out_adj, from, [to], &[to | &1]),
            in_adj: Map.update(g.in_adj, to, [from], &[from | &1])
        }
    end
  end

  def remove_edge(%__MODULE__{} = g, from, to) do
    %{
      g
      | edges: MapSet.delete(g.edges, {from, to}),
        out_adj: Map.update(g.out_adj, from, [], &List.delete(&1, to)),
        in_adj: Map.update(g.in_adj, to, [], &List.delete(&1, from))
    }
  end

  @doc "Kahn's algorithm. Returns nodes in dependency order."
  @spec topological_sort(t()) :: {:ok, [node_id()]} | {:error, :cycle_detected}
  def topological_sort(%__MODULE__{} = g) do
    in_degrees =
      Map.new(g.nodes, fn id ->
        {id, length(Map.get(g.in_adj, id, []))}
      end)

    zeros =
      in_degrees
      |> Enum.filter(fn {_, d} -> d == 0 end)
      |> Enum.map(&elem(&1, 0))

    do_kahn(zeros, in_degrees, g.out_adj, MapSet.size(g.nodes), [])
  end

  @doc """
  All downstream dependents of `id` (transitive closure, excluding `id` itself).
  Useful for dirty propagation.
  """
  def dependents(%__MODULE__{} = g, id) do
    bfs(Map.get(g.out_adj, id, []), g.out_adj, MapSet.new())
  end

  @doc "All upstream dependencies of `id` (transitive, excluding `id`)."
  def dependencies(%__MODULE__{} = g, id) do
    bfs(Map.get(g.in_adj, id, []), g.in_adj, MapSet.new())
  end

  @doc "Roots (no incoming edges)."
  @spec roots(t()) :: [node_id()]
  def roots(%__MODULE__{} = g) do
    Enum.filter(g.nodes, fn id -> Map.get(g.in_adj, id, []) == [] end)
  end

  @doc "Leaves (no outgoing edges)."
  @spec leaves(t()) :: [node_id()]
  def leaves(%__MODULE__{} = g) do
    Enum.filter(g.nodes, fn id -> Map.get(g.out_adj, id, []) == [] end)
  end

  # ── private ──

  defp do_kahn([], _in_degrees, _out_adj, total, acc) do
    if length(acc) == total, do: {:ok, Enum.reverse(acc)}, else: {:error, :cycle_detected}
  end

  defp do_kahn([id | rest], in_degrees, out_adj, total, acc) do
    neighbors = Map.get(out_adj, id, [])

    {new_degs, new_zeros} =
      Enum.reduce(neighbors, {in_degrees, rest}, fn n, {degs, zs} ->
        d = degs[n] - 1
        degs = Map.put(degs, n, d)
        if d == 0, do: {degs, [n | zs]}, else: {degs, zs}
      end)

    do_kahn(new_zeros, new_degs, out_adj, total, [id | acc])
  end

  defp bfs([], _adj, visited), do: visited

  defp bfs([id | rest], adj, visited) do
    if MapSet.member?(visited, id) do
      bfs(rest, adj, visited)
    else
      neighbors = Map.get(adj, id, [])
      bfs(neighbors ++ rest, adj, MapSet.put(visited, id))
    end
  end
end
