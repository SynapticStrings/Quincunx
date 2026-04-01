defmodule Quincunx.Editor.HistoryTest do
  use ExUnit.Case

  alias Quincunx.Topology.Graph.{Node, Edge}

  describe "Operation" do
    import Quincunx.Editor.History.Operation

    test "topology?/1" do
      ## YES!!
      assert topology?({:add_node, %Node{}})
      assert topology?({:update_node, :foo, %Node{}})
      assert topology?({:update_node, :foo, fn node -> %{node | impl: Dummy} end})
      assert topology?({:remove_node, :foo})
      assert topology?({:add_edge, %Edge{}})
      assert topology?({:remove_edge, %Edge{}})

      ## No..
      refute topology?({:set_intervention, {:port, :foo, :bar}, :input, "Foo"})
      refult topology?({:remove_intervention, {:port, "foo", "bar"}, :override})
      refult topology?({:clear_intervention, {:port, "foo", "bar"}})
    end
  end

  describe "Push operation" do
    # ...
  end

  describe "Do, Undo and Redo" do
    test "op will drop out(copy)" do
      # ...
    end
  end
end
