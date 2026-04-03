defmodule Quincunx.Editor.HistoryResolverTest do
  use ExUnit.Case

  import Quincunx.Editor.History.Resolver
  alias Quincunx.Editor.History
  alias Quincunx.Topology.Graph.{Node, Edge}
  import QuincunxTest.GraphFactory
  alias QuincunxTest.DummyOrchidStep, as: S

  describe "Normal resolve behaviour" do
    test "resolve required a graph and history records" do
      assert {%Quincunx.Topology.Graph{}, %{}} =
               resolve(History.new(), build_finin_and_fanout_dag())
    end

    test "when history records has topology" do
      records =
        History.new()
        |> History.push({:remove_node, :step4})
        |> History.push(
          {:add_node, %Node{id: :new_step4, container: S.DummyStep4, inputs: [:in], outputs: [:out1, :out2]}}
        )
        |> History.push({:add_edge, Edge.new(:step3, :out, :new_step4, :in)})
        |> History.push({:remove_edge, Edge.new(:step3, :out, :new_step4, :in)})
        |> History.push({:add_edge, Edge.new(:step3, :out, :new_step4, :in)})
        |> History.push({:update_node, :step2, &(&1)})

      assert {%Quincunx.Topology.Graph{}, %{}} =
               resolve(records, build_finin_and_fanout_dag())
    end

    test "when history records has intervention" do
      records =
        History.new()
        |> History.push({:set_intervention, {:port, :step1, :in}, :input, "Foo"})
        |> History.push({:clear_intervention, {:port, :step1, :in}})

      assert {%Quincunx.Topology.Graph{}, %{}} =
               resolve(records, build_finin_and_fanout_dag())
    end
  end
end
