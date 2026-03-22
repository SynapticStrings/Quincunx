defmodule Quincunx.SegmentBatchTest do
  use ExUnit.Case

  alias Quincunx.Editor.{Segment, History}
  alias Quincunx.Topology.{Graph, Cluster}
  alias Quincunx.Compiler.RecipeBundle
  alias Quincunx.Topology.Graph.{Node, Edge}

  defp build_graph_v1 do
    Graph.new()
    |> Graph.add_node(%Node{
      id: :node_a,
      impl: fn _, _ -> {:ok, Orchid.Param.new(:mid1, :any)} end,
      inputs: [:in],
      outputs: [:mid]
    })
    |> Graph.add_node(%Node{
      id: :node_b,
      impl: fn _, _ -> {:ok, Orchid.Param.new(:out, :any)} end,
      inputs: [:mid],
      outputs: [:out]
    })
    |> Graph.add_edge(Edge.new(:node_a, :mid, :node_b, :mid))
  end

  defp build_graph_v2 do
    Graph.new()
    |> Graph.add_node(%Node{id: :node_d, inputs: [:in], outputs: [:out]})
  end

  test "批量编译：同构图复用拓扑，但保留独立参数 (Interventions)" do
    graph_v1 = build_graph_v1()

    cluster_v1 = %Cluster{
      node_colors: %{
        node_a: :cpu_cluster,
        node_b: :gpu_cluster
      }
    }

    hist1 =
      History.new()
      |> History.push({:set_intervention, {:port, :node_b, :mid}, :override, 100})

    seg1 = Segment.new(:seg_1, graph_v1, cluster_v1)

    seg1 = %{seg1 | history: hist1}

    hist2 =
      History.new()
      |> History.push({:set_intervention, {:port, :node_b, :mid}, :override, 200})

    seg2 = Segment.new(:seg_2, graph_v1, cluster_v1)
    seg2 = %{seg2 | history: hist2}

    seg3 =
      Segment.new(:seg_3, build_graph_v2(), %Cluster{node_colors: %{node_d: :cpu_cluster}})
      |> Segment.apply_operation({:set_intervention, {:port, :node_d, :in}, :mask, 80})

    assert {:ok, results} = Segment.compile_to_recipes([seg1, seg2, seg3])

    assert length(results) == 3

    res_seg1 = Enum.find(results, &(&1.id == :seg_1))
    res_seg2 = Enum.find(results, &(&1.id == :seg_2))
    res_seg3 = Enum.find(results, &(&1.id == :seg_3))

    assert length(res_seg1.recipe_bundles) == 2

    gpu_recipe_1 = Enum.find(res_seg1.recipe_bundles, &(&1.recipe.name == :gpu_cluster))
    assert RecipeBundle.get_intervention(gpu_recipe_1, {:port, :node_b, :mid}, :override) == 100

    gpu_recipe_2 = Enum.find(res_seg2.recipe_bundles, &(&1.recipe.name == :gpu_cluster))

    assert assert RecipeBundle.get_intervention(gpu_recipe_2, {:port, :node_b, :mid}, :override) == 200

    assert length(res_seg3.recipe_bundles) == 1
    cpu_recipe_3 = hd(res_seg3.recipe_bundles)

    assert cpu_recipe_3.recipe.name == :cpu_cluster

    assert RecipeBundle.get_intervention(cpu_recipe_3, {:port, :node_d, :in}, :mask) ==
             80

    assert RecipeBundle.put_intervention(cpu_recipe_3, {:port, :node_d, :in}, :mask, 0)
           |> RecipeBundle.get_intervention({:port, :node_d, :in}, :mask) ==
             0
  end

  test "错误处理：包含环路的 Segment 会导致批处理失败" do
    graph_cycle =
      Graph.new()
      |> Graph.add_node(%Node{id: :loop, inputs: [:val], outputs: [:res]})
      |> Graph.add_edge(Edge.new(:loop, :res, :loop, :val))

    seg_ok = Segment.new(:ok, build_graph_v1())
    seg_err = Segment.new(:err, graph_cycle)

    assert {:error, :cycle_detected} = Segment.compile_to_recipes([seg_ok, seg_err])
  end
end
