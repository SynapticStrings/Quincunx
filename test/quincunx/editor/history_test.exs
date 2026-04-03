defmodule Quincunx.Editor.HistoryTest do
  use ExUnit.Case

  alias Quincunx.Topology.Graph.{Node, Edge}
  import Quincunx.Editor.History

  describe "Operation" do
    import Quincunx.Editor.History.Operation

    test "topology?/1" do
      ## YES!!
      assert topology?({:add_node, %Node{}})
      assert topology?({:update_node, :foo, %Node{}})
      assert topology?({:update_node, :foo, fn node -> %{node | container: Dummy} end})
      assert topology?({:remove_node, :foo})
      assert topology?({:add_edge, %Edge{}})
      assert topology?({:remove_edge, %Edge{}})

      ## No..
      refute topology?({:set_intervention, {:port, :foo, :bar}, :input, "Foo"})
      refute topology?({:remove_intervention, {:port, "foo", "bar"}, :override})
      refute topology?({:clear_intervention, {:port, "foo", "bar"}})
    end
  end

  describe "Push operation" do
    test "push/2" do
      new = new()
      record1 = push(new, {:add_node, %Node{}})
      record2 = push(record1, {:set_intervention, {:port, :foo, :bar}, :input, "Foo"})

      assert record1.undo_stack == [{:add_node, %Node{}}]

      assert record2.undo_stack == [
               {:set_intervention, {:port, :foo, :bar}, :input, "Foo"},
               {:add_node, %Node{}}
             ]
    end
  end

  describe "Do, Undo and Redo" do
    test "op will drop out(copy)" do
      record = new()
       |> push({:add_node, %Node{id: :node_1}})
       |> push({:add_node, %Node{id: :node_2}})
       |> push({:add_edge, Edge.new(:node_1, :out, :node_2, :in)})
       |> push({:set_intervention, {:foo, :node_1, :in}, :input, "Aha!"})

       assert {undid, {:set_intervention, {:foo, :node_1, :in}, _, _}} = undo(record)
       assert {^record, _} = redo(undid)
    end

    test "blank history will return nil" do
      assert {_, nil} = new() |> undo()
      assert {_, nil} = new() |> redo()
    end
  end
end
