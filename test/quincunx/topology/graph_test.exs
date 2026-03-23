defmodule Quincunx.Topology.GraphTest do
  use ExUnit.Case

  alias Quincunx.Topology.Graph.Node
  alias QuincunxTest.DummyOrchidStep.{DummyStep1}

  describe "Item creation" do
    test "same step impl can use different node ids" do
      node_1 = %Node{id: :node_1, impl: DummyStep1, inputs: [:in], outputs: [:out]}
      node_2 = %Node{id: :node_2, impl: DummyStep1, inputs: [:in], outputs: [:out]}

      assert node_1 != node_2
      assert Orchid.Param.get_payload(node_1.impl.run(Orchid.Param.new(:node_1_in, :binary, "NodeIn"))) ==
        Orchid.Param.get_payload(node_2.impl.run(Orchid.Param.new(:node_2_in, :binary, "NodeIn")))
    end

    # test "Edge.new/4"
  end

  describe "Item operation" do
  end

  describe "Sort graph" do
  end
end
