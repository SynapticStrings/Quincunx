defmodule Quincunx.Topology.ClusterTest do
  use ExUnit.Case

  import Quincunx.Topology.Graph, only: [topological_sort: 1]
  import Quincunx.Topology.Cluster
  import QuincunxTest.GraphFactory

  alias Quincunx.Topology.Cluster

  setup do
    graph =
      build_finin_and_fanout_dag()

    {:ok, sorted_nodes} = topological_sort(graph)

    %{sorted_graph: sorted_nodes, edges: graph.edges}
  end

  describe "apply node_colors" do
    test "set default color when set declaration", %{sorted_graph: nodes, edges: edges} do
      assert [:default_cluster] ==
               paint_graph(nodes, edges, %Cluster{}) |> Map.values() |> Enum.uniq()
    end

    # 有声明是什么
    test "set new color when has node_colors", %{sorted_graph: nodes, edges: edges} do
      assert paint_graph(nodes, edges, %Cluster{node_colors: %{step4: :foo}}) |> Map.get(:step4) ==
               :foo
    end

    # 有声明的下游是什么
    test "color can be propogated downstream", %{sorted_graph: nodes, edges: edges} do
      graph_colors = paint_graph(nodes, edges, %Cluster{node_colors: %{step1: :foo, step2: :bar}})

      assert get_in(graph_colors, [:step3]) == [:foo, :bar] |> Enum.sort()
    end
  end

  # 这个 feature 还没有实现
  describe "apply merge_groups" do
    # After implement related functions.

    # 期望是遍历一遍，遍历完了就不管了。
  end
end
