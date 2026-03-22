defmodule TopologyCompilerClustersTest do
  use ExUnit.Case

  alias Quincunx.Topology.{Graph, Cluster}
  alias Quincunx.Topology.Graph.{Node, Edge}
  alias Quincunx.Compiler

  test "two-cluster topology produces correct boundaries" do
    # Node A (cpu) -> Node B (gpu) -> Node C (cpu, gpu)
    graph = Graph.new()
      |> Graph.add_node(%Node{id: :a, impl: fn [i], _ -> {:ok, i} end, inputs: [:in], outputs: [:out]})
      |> Graph.add_node(%Node{id: :b, impl: fn [i], _ -> {:ok, i} end, inputs: [:in], outputs: [:out]})
      |> Graph.add_node(%Node{id: :c, impl: fn [i], _ -> {:ok, i} end, inputs: [:in], outputs: [:out]})
      |> Graph.add_edge(Edge.new(:a, :out, :b, :in))
      |> Graph.add_edge(Edge.new(:b, :out, :c, :in))

    cluster = %Cluster{node_colors: %{a: :cpu, b: :gpu, c: :cpu2}}

    {:ok, bundles} = Compiler.compile_graph(graph, cluster)

    # Must produce multiple bundles with correct requires/exports
    assert length(bundles) >= 2

    gpu_bundle = Enum.find(bundles, & :gpu in List.wrap(&1.recipe.name))
    assert :a_out in gpu_bundle.requires
    assert :b_out in gpu_bundle.exports
  end

end
