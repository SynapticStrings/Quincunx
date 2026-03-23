defmodule Quincunx.Topology.GraphTest do
  use ExUnit.Case

  alias Quincunx.Topology.Graph.Node
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

    # test "Edge.new/4"
  end

  describe "Item operation" do
  end

  describe "Sort graph" do
  end
end
