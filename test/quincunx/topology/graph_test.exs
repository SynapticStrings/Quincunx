defmodule Quincunx.Topology.GraphTest do
  use ExUnit.Case

  import Quincunx.Topology.Graph
  alias Quincunx.Topology.Graph.{Node, Edge}
  alias QuincunxTest.DummyOrchidStep.{DummyStep1}

  describe "Item creation" do
    test "same step impl can use different node ids" do
      node_1 = %Node{id: :node_1, impl: DummyStep1, inputs: [:in], outputs: [:out]}
      node_2 = %Node{id: :node_2, impl: DummyStep1, inputs: [:in], outputs: [:out]}

      assert Map.from_struct(node_1) != Map.from_struct(node_2)

      {:ok, res1} = node_1.impl.run(%Orchid.Param{payload: "NodeIn"}, [])
      {:ok, res2} = node_2.impl.run(%Orchid.Param{payload: "NodeIn"}, [])

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
      port_ref = {:port, :foo, :bar}

      assert PortRef.to_orchid_key(port_ref) == :foo_bar
      assert PortRef.to_orchid_binary_key(port_ref) == "foo_bar"
    end

    test "Quincunx.Topology.Graph.add_node/2" do
      graph =
        new() |> add_node(%Node{id: :node_1, impl: DummyStep1, inputs: [:in], outputs: [:out]})

      assert get_in(graph.nodes.node_1.impl) == DummyStep1
    end

    # add_edge
    # 可以悬空
    # （悬空边会在排序/Resolve中被抛弃）

    # remove_node
    # 移除相关边

    # remove_edge
  end

  describe "Sort graph" do
    # 构造一组图

    # 入度为0在前面

    # 最后入度为0的在后面
  end
end
