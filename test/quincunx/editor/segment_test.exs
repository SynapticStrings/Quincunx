defmodule Quincunx.Editor.SegmentTest do
  use ExUnit.Case

  import Quincunx.Editor.Segment
  alias Quincunx.Topology.Graph
  alias Quincunx.Editor.History
  import QuincunxTest.GraphFactory

  describe "Segment creation" do
    test "new/1" do
      assert %Quincunx.Editor.Segment{} = new("SessionID", Graph.new())
    end
  end

  describe "Attach history operation" do
    test "apply_operarion, undo and redo" do
      new_seg = new("SessionID", Graph.new())
      |> apply_operation({:new_intervention, {:port, :foo, :bar}, :override, "Aha!!"})

      {new_seg, _op} = undo(new_seg)
      {new_seg, _op} = redo(new_seg)

      assert new_seg.history.undo_stack == [{:new_intervention, {:port, :foo, :bar}, :override, "Aha!!"}]
    end
  end

  describe "Segment modification" do
    test "inject_graph_and_interventions/2 will reset history" do
      old_seg = new("SessionID", Graph.new())
      new_seg = inject_graph_and_interventions(old_seg, build_finin_and_fanout_dag(), %{})

      assert new_seg.history == %History{}
    end

    test "inject_graph_and_interventions/3 will resume history if set clear_history false" do
      new_seg = new("SessionID", Graph.new())
      |> apply_operation({:new_intervention, {:port, :foo, :bar}, :override, "Aha!!"})
      |> inject_graph_and_interventions(build_finin_and_fanout_dag(), %{}, false)

      refute new_seg.history == %History{}
    end
  end
end
