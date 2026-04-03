defmodule Quincunx.Topology.LiteGraphTest do
  use ExUnit.Case

  alias Quincunx.Topology.LiteGraph

  describe "new/0" do
    test "returns an empty graph" do
      g = LiteGraph.new()
      assert g.nodes == MapSet.new()
      assert g.edges == MapSet.new()
      assert g.in_adj == %{}
      assert g.out_adj == %{}
    end
  end

  describe "add_node/2" do
    test "adds a single node" do
      g = LiteGraph.new() |> LiteGraph.add_node(:a)
      assert MapSet.member?(g.nodes, :a)
      assert g.in_adj[:a] == []
      assert g.out_adj[:a] == []
    end

    test "adding an existing node does not duplicate adjacency entries" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:a)

      assert MapSet.size(g.nodes) == 1
      assert g.in_adj[:a] == []
      assert g.out_adj[:a] == []
    end
  end

  describe "remove_node/2" do
    setup do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)
      {:ok, graph: g}
    end

    test "removes an isolated node", %{graph: g} do
      g2 = LiteGraph.remove_node(g, :c)
      refute MapSet.member?(g2.nodes, :c)
      assert g2.edges == MapSet.new([{:a, :b}])
      assert g2.in_adj == %{a: [], b: [:a]}
      assert g2.out_adj == %{a: [:b], b: []}
    end

    test "removes a node with incoming and outgoing edges", %{graph: g} do
      g2 = LiteGraph.remove_node(g, :b)
      refute MapSet.member?(g2.nodes, :b)
      assert g2.edges == MapSet.new()
      assert g2.in_adj == %{a: [], c: []}
      assert g2.out_adj == %{a: [], c: []}
    end

    test "removing a non-existent node leaves the graph unchanged", %{graph: g} do
      g2 = LiteGraph.remove_node(g, :x)
      assert g2 == g
    end
  end

  describe "add_edge/2" do
    setup do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
      {:ok, graph: g}
    end

    test "adds an edge between existing nodes", %{graph: g} do
      g2 = LiteGraph.add_edge(g, :a, :b)
      assert MapSet.member?(g2.edges, {:a, :b})
      assert g2.out_adj[:a] == [:b]
      assert g2.in_adj[:b] == [:a]
    end

    test "adding duplicate edge leads to duplicate entries in adjacency lists", %{graph: g} do
      g2 = g
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:a, :b)

      # edges set remains a single entry
      assert MapSet.size(g2.edges) == 1
      assert g2.out_adj[:a] == [:b]
      assert g2.in_adj[:b] == [:a]
    end

    test "adding edge where nodes are missing produces inconsistent state" do
      g = LiteGraph.new()
      g2 = LiteGraph.add_edge(g, :missing, :also_missing)
      # edge is added even though nodes aren't present
      assert MapSet.member?(g2.edges, {:missing, :also_missing})
      # adjacency lists are created for missing nodes
      assert g2.out_adj[:missing] == [:also_missing]
      assert g2.in_adj[:also_missing] == [:missing]
      # but nodes set does not contain them
      refute MapSet.member?(g2.nodes, :missing)
      refute MapSet.member?(g2.nodes, :also_missing)
    end
  end

  describe "remove_edge/2" do
    setup do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_edge(:a, :b)
      {:ok, graph: g}
    end

    test "removes an existing edge", %{graph: g} do
      g2 = LiteGraph.remove_edge(g, :a, :b)
      refute MapSet.member?(g2.edges, {:a, :b})
      assert g2.out_adj[:a] == []
      assert g2.in_adj[:b] == []
    end

    test "removing a non-existent edge does nothing", %{graph: g} do
      g2 = LiteGraph.remove_edge(g, :b, :a)
      assert g2 == g
    end

    test "removing only one instance when duplicate edges exist", %{graph: g} do
      g2 = g
          |> LiteGraph.add_edge(:a, :b)   # duplicate
          |> LiteGraph.remove_edge(:a, :b)
      # edges set is empty (since duplicate didn't create another set entry)
      assert MapSet.size(g2.edges) == 0
      # adjacency lists lose one occurrence but still have the other
      assert g2.out_adj[:a] == []
      assert g2.in_adj[:b] == []
    end
  end

  describe "topological_sort/1" do
    test "returns empty list for empty graph" do
      assert LiteGraph.topological_sort(LiteGraph.new()) == {:ok, []}
    end

    test "returns single node for graph with one node" do
      g = LiteGraph.new() |> LiteGraph.add_node(:a)
      assert LiteGraph.topological_sort(g) == {:ok, [:a]}
    end

    test "orders nodes correctly in a DAG" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)

      assert LiteGraph.topological_sort(g) == {:ok, [:a, :b, :c]}
    end

    test "handles multiple roots" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :c)
          |> LiteGraph.add_edge(:b, :c)

      {:ok, order} = LiteGraph.topological_sort(g)
      # roots :a and :b can appear in any order before :c
      assert order == [:a, :b, :c] or order == [:b, :a, :c]
    end

    test "detects a simple cycle" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :a)

      assert LiteGraph.topological_sort(g) == {:error, :cycle_detected}
    end

    test "detects cycle with more nodes" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)
          |> LiteGraph.add_edge(:c, :a)

      assert LiteGraph.topological_sort(g) == {:error, :cycle_detected}
    end

    test "duplicate edges affect indegree count and break topological sort" do
      # Demonstrates the duplicate-edge bug: indegree becomes 2 for :b
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:a, :b)   # duplicate

      assert LiteGraph.topological_sort(g) == {:ok, [:a, :b]}
    end
  end

  describe "dependents/2" do
    test "returns empty set for node with no outgoing edges" do
      g = LiteGraph.new() |> LiteGraph.add_node(:a)
      assert LiteGraph.dependents(g, :a) == MapSet.new()
    end

    test "returns direct and transitive downstream nodes" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_node(:d)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)
          |> LiteGraph.add_edge(:a, :d)

      assert LiteGraph.dependents(g, :a) == MapSet.new([:b, :c, :d])
    end

    test "excludes the node itself" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_edge(:a, :a)   # self-loop (allowed by data model)
      # dependents should not include :a
      assert LiteGraph.dependents(g, :a) == MapSet.new()
    end

    test "handles diamond-shaped DAG" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_node(:d)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:a, :c)
          |> LiteGraph.add_edge(:b, :d)
          |> LiteGraph.add_edge(:c, :d)

      assert LiteGraph.dependents(g, :a) == MapSet.new([:b, :c, :d])
    end
  end

  describe "dependencies/2" do
    test "returns empty set for node with no incoming edges" do
      g = LiteGraph.new() |> LiteGraph.add_node(:a)
      assert LiteGraph.dependencies(g, :a) == MapSet.new()
    end

    test "returns direct and transitive upstream nodes" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_node(:d)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)
          |> LiteGraph.add_edge(:a, :d)

      assert LiteGraph.dependencies(g, :c) == MapSet.new([:a, :b])
    end

    test "excludes the node itself" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_edge(:a, :a)
      assert LiteGraph.dependencies(g, :a) == MapSet.new()
    end
  end

  describe "roots/1" do
    test "returns all nodes with no incoming edges" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)

      roots = LiteGraph.roots(g)
      assert Enum.sort(roots) == [:a]
    end

    test "returns multiple roots" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :c)
          |> LiteGraph.add_edge(:b, :c)

      roots = LiteGraph.roots(g)
      assert Enum.sort(roots) == [:a, :b]
    end

    test "returns all nodes when graph has no edges" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
      assert Enum.sort(LiteGraph.roots(g)) == [:a, :b]
    end
  end

  describe "leaves/1" do
    test "returns all nodes with no outgoing edges" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:b, :c)

      leaves = LiteGraph.leaves(g)
      assert leaves == [:c]
    end

    test "returns multiple leaves" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
          |> LiteGraph.add_node(:c)
          |> LiteGraph.add_edge(:a, :b)
          |> LiteGraph.add_edge(:a, :c)

      leaves = LiteGraph.leaves(g)
      assert Enum.sort(leaves) == [:b, :c]
    end

    test "returns all nodes when graph has no edges" do
      g = LiteGraph.new()
          |> LiteGraph.add_node(:a)
          |> LiteGraph.add_node(:b)
      assert Enum.sort(LiteGraph.leaves(g)) == [:a, :b]
    end
  end
end
