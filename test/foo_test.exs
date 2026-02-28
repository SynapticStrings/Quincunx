defmodule Quincunx.SegmentBatchTest do
  use ExUnit.Case

  alias Quincunx.Session.Segment
  alias Quincunx.Session.Segment.{Graph, History}
  alias Quincunx.Session.Segment.Graph.{Node, Edge, Cluster}

  # --- 辅助函数：构建一个基础图 ---
  # A(input) -> B(process) -> C(output)
  defp build_graph_v1 do
    Graph.new()
    |> Graph.add_node(%Node{id: :node_a, impl: fn _, _ -> {:ok, Orchid.Param.new(:mid1, :any)} end, inputs: [:in], outputs: [:mid]})
    |> Graph.add_node(%Node{id: :node_b, impl: fn _, _ -> {:ok, Orchid.Param.new(:out, :any)} end, inputs: [:mid], outputs: [:out]})
    |> Graph.add_edge(Edge.new(:node_a, :mid, :node_b, :mid))
  end

  # --- 辅助函数：构建另一个结构的图（用于验证异构分组）---
  # Single Node D
  defp build_graph_v2 do
    Graph.new()
    |> Graph.add_node(%Node{id: :node_d, inputs: [:in], outputs: [:out]})
  end

  test "批量编译：同构图复用拓扑，但保留独立参数 (Interventions)" do
    graph_v1 = build_graph_v1()

    # 定义分簇：Node A 在 CPU，Node B 在 GPU
    cluster_v1 = %Cluster{
      node_colors: %{
        node_a: :cpu_cluster,
        node_b: :gpu_cluster
      }
    }

    # === 准备数据 ===

    # Segment 1: Override node_a 的 :in 端口为 100
    hist1 =
      History.new()
      |> History.push({:override, {:port, :node_b, :mid}, 100})

    seg1 = Segment.new(:seg_1, graph_v1, cluster_v1)
    seg1 = %{seg1 | history: hist1} # 手动注入 history，模拟编辑

    # Segment 2: 同构图，但 Override node_a 的 :in 端口为 200
    hist2 =
      History.new()
      |> History.push({:override, {:port, :node_b, :mid}, 200})

    seg2 = Segment.new(:seg_2, graph_v1, cluster_v1)
    seg2 = %{seg2 | history: hist2}

    # Segment 3: 完全不同的图结构 (Graph V2)
    # 这里的 Cluster 可以为空，默认为默认簇
    seg3 = Segment.new(:seg_3, build_graph_v2(), %Cluster{node_colors: %{node_d: :cpu_cluster}})

    # === 执行批量编译 ===
    # 期望结果：返回 {:ok, [compiled_seg1, compiled_seg2, compiled_seg3]}
    assert {:ok, results} = Segment.compile_to_recipes([seg1, seg2, seg3])

    # === 验证 ===

    # 1. 验证数量
    assert length(results) == 3

    # 提取编译后的 Segment
    res_seg1 = Enum.find(results, & &1.id == :seg_1)
    res_seg2 = Enum.find(results, & &1.id == :seg_2)
    res_seg3 = Enum.find(results, & &1.id == :seg_3)

    # 2. 验证 Segment 1 (Graph V1, Value 100)
    # 按照 Cluster 定义，应该生成 CPU 和 GPU 两个 Recipe
    assert length(res_seg1.compiled_recipes) == 2

    # 找到 CPU Recipe (它包含 node_a)
    gpu_recipe_1 = Enum.find(res_seg1.compiled_recipes, &(&1.recipe.name == :gpu_cluster))
    # 验证 Lily.Compiler.bind_interventions 是否成功将 100 注入
    # 根据 Lily 的设计，绑定后的数据通常存在 Recipe 的 overrides 或 inputs 字段中
    # 这里假设是一个类似 %{inputs: %{key => val}, overrides: ...} 的结构
    # 或者是一个携带数据的 Bundle 结构
    assert gpu_recipe_1.overrides[{:port, :node_b, :mid}] == 100

    # 3. 验证 Segment 2 (Graph V1, Value 200)
    gpu_recipe_2 = Enum.find(res_seg2.compiled_recipes, &(&1.recipe.name == :gpu_cluster))
    # 关键验证：虽然拓扑和 Segment 1 一样，但数据必须是独立的 200
    assert gpu_recipe_2.overrides[{:port, :node_b, :mid}] == 200

    # 确保没有发生数据泄漏
    assert gpu_recipe_1.overrides != gpu_recipe_2.overrides

    # 4. 验证 Segment 3 (异构图)
    # 它的 Recipe 结构应该完全不同
    assert length(res_seg3.compiled_recipes) == 1
    cpu_recipe_3 = hd(res_seg3.compiled_recipes)
    # 应该包含 node_d
    # 这里我们通过检查 export 或 name 来验证它是针对 Graph V2 编译的
    # (具体验证依赖 Orchid Recipe 的内部结构，这里假设它是一个包含 steps 的 Recipe)
    # 如果是 Cluster 模式，compile 应该返回 list of recipes
    assert cpu_recipe_3.recipe.name == :cpu_cluster
  end

  test "错误处理：包含环路的 Segment 会导致批处理失败" do
    # 构造一个环路图 A -> A
    graph_cycle =
      Graph.new()
      |> Graph.add_node(%Node{id: :loop, inputs: [:val], outputs: [:res]})
      |> Graph.add_edge(Edge.new(:loop, :res, :loop, :val))

    seg_ok = Segment.new(:ok, build_graph_v1())
    seg_err = Segment.new(:err, graph_cycle)

    # Lily.Compiler.compile/2 遇到环路应该返回 {:error, :cycle_detected}
    # Segment.compile_to_recipes/1 应该捕获这个错误并停止
    assert {:error, :cycle_detected} = Segment.compile_to_recipes([seg_ok, seg_err])
  end
end
