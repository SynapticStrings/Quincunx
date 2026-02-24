defmodule Quincunx.Segment.Compiler do
  alias Quincunx.Dependency

  def compile(%Dependency{} = _graph, _state) do
    # 1. Coloring the Nodes
  end
end

# @doc """
# 将 Recorder 折叠出的有效状态，结合切分策略，编译为 Recipe 序列。
# """
# def compile(effective_state, cluster_declara \\ default_declara()) do
#   %{resolved_graph: graph, data_state: data_state} = effective_state
#   overrides = Map.get(data_state, :overrides, %{})

#   # ==========================================
#   # 步骤 1: 染色分簇 (Coloring)
#   # ==========================================
#   # 返回 %{node_name => cluster_id}
#   node_colors = paint_graph(graph, cluster_declara)

#   # 按照 cluster_id 将 Node 分组，并按拓扑排序排列簇的执行顺序
#   # clusters = [{cluster_id, [Node_A, Node_B]}, ...]
#   clusters = group_and_sort_clusters(graph, node_colors)

#   # ==========================================
#   # 步骤 2: 逐个簇构建 Recipe
#   # ==========================================
#   Enum.map(clusters, fn {cluster_id, nodes_in_cluster} ->
#     build_cluster_recipe(cluster_id, nodes_in_cluster, graph, overrides, node_colors)
#   end)
#   |> merge_recipes_if_needed(cluster_declara.merge_groups) # (可选) 依据策略合并
# end

# # 构建单个 Recipe 的核心逻辑
# defp build_cluster_recipe(cluster_id, nodes, graph, overrides, node_colors) do
#   # ------------------------------------------
#   # 2.1 翻译 Node 为 Orchid.Step
#   # ------------------------------------------
#   steps = Enum.map(nodes, fn node ->
#     # 找出连向该节点的所有 Edge，和从该节点出发的所有 Edge
#     in_edges = Dependency.get_in_edges(graph, node.name)
#     out_edges = Dependency.get_out_edges(graph, node.name)

#     # 这里的 inputs 和 outputs 直接使用严格的 edge_key
#     Step.new(
#       name: node.name,
#       impl: node.impl,
#       inputs: Enum.map(in_edges, &edge_to_key/1),
#       outputs: Enum.map(out_edges, &edge_to_key/1),
#       opts: node.step_opts # Orchid 的原生配置
#     )
#   end)

#   # ------------------------------------------
#   # 2.2 计算边界 (Requires & Exports)
#   # ------------------------------------------
#   # 当前簇里的节点，依赖了【不属于当前簇】的节点的输出，这些边被切断了！
#   # 它们必须向外部 (Renderer 状态机/黑板) 索要。
#   boundary_requires =
#     get_all_in_edges_for_cluster(nodes, graph)
#     |> Enum.reject(fn edge -> node_colors[edge.from_node] == cluster_id end)
#     |> Enum.map(&edge_to_key/1)

#   # 当前簇里的节点，其输出被【不属于当前簇】的节点依赖，也切断了！
#   # 必须导出到外部，供下游 Recipe 使用。
#   boundary_exports =
#     get_all_out_edges_for_cluster(nodes, graph)
#     |> Enum.reject(fn edge -> node_colors[edge.to_node] == cluster_id end)
#     |> Enum.map(&edge_to_key/1)

#   # ------------------------------------------
#   # 2.3 处理 Override Baggage (Hook 的弹药)
#   # ------------------------------------------
#   # 我们找出所有指向当前簇内节点的、被用户 override 的边
#   cluster_overrides =
#     overrides
#     |> Enum.filter(fn {edge, _value} -> edge.to_node in Enum.map(nodes, & &1.name) end)
#     |> Map.new(fn {edge, value} -> {edge_to_key(edge), value} end)

#   # ------------------------------------------
#   # 2.4 组装 Recipe
#   # ------------------------------------------
#   Recipe.new(
#     name: cluster_id,
#     steps: steps,
#     requires: boundary_requires,
#     exports: boundary_exports,
#     # 将 override 打包进行李箱，Orchid 内部完全不知道这是啥
#     baggage: %{quincunx_overrides: cluster_overrides}
#   )
# end
