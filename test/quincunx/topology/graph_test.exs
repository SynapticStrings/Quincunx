defmodule Quincunx.Topology.GraphTest do
  use ExUnit.Case

  import Quincunx.Topology.Graph
  alias Quincunx.Topology.Graph.{Node, Edge}
  alias QuincunxTest.DummyOrchidStep.{DummyStep1, DummyStep2}

  import QuincunxTest.GraphFactory

  describe "Item creation" do
    test "same step impl can use different node ids" do
      node_1 = %Node{id: :node_1, container: DummyStep1, inputs: [:in], outputs: [:out]}
      node_2 = %Node{id: :node_2, container: DummyStep1, inputs: [:in], outputs: [:out]}

      assert Map.from_struct(node_1) != Map.from_struct(node_2)

      {:ok, res1} = node_1.container.run(%Orchid.Param{payload: "NodeIn"}, [])
      {:ok, res2} = node_2.container.run(%Orchid.Param{payload: "NodeIn"}, [])

      assert Orchid.Param.get_payload(res1) == Orchid.Param.get_payload(res2)
    end

    test "Edge.new/4" do
      edge = Edge.new(:node_a, :port_out, :node_b, :port_in)

      assert edge.from_node == :node_a
      assert edge.from_port == :port_out
      assert edge.to_node == :node_b
      assert edge.to_port == :port_in
    end
  end

  describe "Item operation" do
    test "PortRef can be converted to Orchid step's io key" do
      alias Quincunx.Topology.Graph.PortRef
      port_ref_with_atom = {:port, :foo, :bar}
      port_ref_with_binary = {:port, :foo, "barr"}

      assert PortRef.to_orchid_key(port_ref_with_atom) == "foo|bar"
      assert PortRef.to_orchid_key(port_ref_with_binary) == "foo|barr"
    end

    test "Quincunx.Topology.Graph.add_node/2" do
      graph =
        new() |> add_node(%Node{id: :node_1, container: DummyStep1, inputs: [:in], outputs: [:out]})

      assert get_in(graph.nodes.node_1.container) == DummyStep1
    end

    # NOTE: 可以悬空
    # （悬空边会在排序/Resolve中被抛弃）
    test "add_edge/2" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        # 重复边会被忽略
        |> add_edge(Edge.new(:a, :out, :b, :in))
        # 自环边也会被忽略
        |> add_edge(Edge.new(:a, :out, :a, :in))

      assert graph.edges |> Enum.count() == 1
      edge = Enum.at(graph.edges, 0)
      assert edge.from_node == :a
      assert edge.to_node == :b
    end

    test "remove_node/2" do
      graph = build_graph_v1()

      graph = remove_node(graph, :node_a)

      assert graph.nodes == %{:node_b => %Node{id: :node_b, container: DummyStep2, inputs: [:mid], outputs: [:out], options: [], extra: %{}}}
      assert graph.edges == MapSet.new()
    end

    test "remove_node/2 when node not exist" do
      old_graph = build_graph_v1()

      graph = remove_node(old_graph, :node_foo)

      assert graph.nodes == old_graph.nodes
      assert graph.edges == old_graph.edges
    end

    test "update_node/2" do
      graph = build_graph_v1()

      graph = update_node(graph, :node_b, %Node{id: :node_b, container: DummyStep1, inputs: [:mid], outputs: [:out], options: [], extra: %{}})

      assert get_in(graph.nodes.node_b.container) == DummyStep1

      graph = update_node(graph, :node_b, fn old_node -> %{old_node | container: DummyStep2} end)

      assert get_in(graph.nodes.node_b.container) == DummyStep2

      new_graph = update_node(graph, :node_c, fn old_node -> %{old_node | container: DummyStep2} end)

      assert graph.nodes == new_graph.nodes
    end

    test "remove_edge/2" do
      edge = Edge.new(:a, :out, :b, :in)
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(edge)

      graph = remove_edge(graph, edge)

      assert graph.edges == MapSet.new()
    end

    test "get_in_edges/2" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :c, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :c, :in))
        |> add_edge(Edge.new(:b, :out, :c, :in))

      in_edges = get_in_edges(graph, :c)
      assert length(in_edges) == 2
      assert Enum.all?(in_edges, &(&1.to_node == :c))
    end

    test "get_out_edges/2" do
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :c, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:a, :out, :c, :in))

      out_edges = get_out_edges(graph, :a)
      assert length(out_edges) == 2
      assert Enum.all?(out_edges, &(&1.from_node == :a))
    end
  end

  describe "Graph Check" do
    test "same?/2" do
      graph1 = build_graph_v1()
      graph2 = build_graph_v1()

      assert same?(graph1, graph2)
    end

    test "same?/2 with more complex scene" do
      graph1 = build_graph_v1()

      # Mock redo & undo
      graph2 = build_graph_v1()
      |> update_node(:node_b, %Node{id: :node_b, container: DummyStep1, inputs: [:mid], outputs: [:out], options: [], extra: %{}})
      |> update_node(:node_b, fn old_node -> %{old_node | container: DummyStep2} end)

      assert same?(graph1, graph2)
    end
  end

  describe "Sort graph" do
    # Construct a DAG containing Fan-in / Fan-out:
    #   Step1 (out) --> Step3 (in1)
    #   Step2 (out) --> Step3 (in2)
    #   Step3 (out) --> Step4 (in)
    # The desired topological order can be [Step1, Step2, Step3, Step4] or [Step2, Step1, Step3, Step4]
    test "topological_sort on fan-in/fan-out graph" do
      graph = build_finin_and_fanout_dag()

      assert {:ok, order} = topological_sort(graph)
      # Verify that the sorting satisfies the dependency relationship.
      idx = fn id -> Enum.find_index(order, &(&1 == id)) end
      assert idx.(:step1) < idx.(:step3)
      assert idx.(:step2) < idx.(:step3)
      assert idx.(:step3) < idx.(:step4)
      # The first two can be in any order, but they must both appear before step3.
      assert order |> Enum.take(2) |> Enum.sort() == [:step1, :step2]
      assert order == [:step1, :step2, :step3, :step4] or order == [:step2, :step1, :step3, :step4]
    end

    test "topological_sort returns error on cycle" do
      # a -> b -> a
      graph =
        new()
        |> add_node(%Node{id: :a, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_node(%Node{id: :b, container: DummyStep1, inputs: [:in], outputs: [:out]})
        |> add_edge(Edge.new(:a, :out, :b, :in))
        |> add_edge(Edge.new(:b, :out, :a, :in))

      assert topological_sort(graph) == {:error, :cycle_detected}
    end
  end
end
