defmodule Quincunx.Dependency.Cluster do
  # 将依赖依照用户选择以及依赖关系分簇
  # 以实现并行控制
  # 人话：将部分很耗费资源的服务单独丢出去
  # 将整个并行改成串行 + 并行
  alias Quincunx.Dependency
  alias Quincunx.Dependency.Node
  @type cluster_name :: atom() | String.t()

  @type color_mixing_strategy ::
          :isolate
          # 强行并入某个特定的簇
          | {:merge_into, cluster_name()}
          # 继承输入中最重/节点最多的簇颜色
          | :dominant_upstream

  @type t :: %__MODULE__{
          # 用户/前端显式指定的节点簇映射 (如 %{:acoustic_model => :cluster_1})
          node_colors: %{Node.name() => cluster_name()},

          # 混色解决策略：当节点依赖了 [cluster_A, cluster_B] 时怎么处理？
          mixing_strategy: color_mixing_strategy(),

          # 用户决定要在这一层直接合并的簇列表，比如 [[:cluster_1, :cluster_2], [:cluster_3]]
          # 这样 Compiler 就会吐出 2 个 Recipe 而不是 3 个
          merge_groups: [{[cluster_name()], cluster_name()}]
        }
  defstruct node_colors: %{},
            mixing_strategy: :isolate,
            merge_groups: []

  @doc "Return `%{node_name => final_cluster_name}`"
  def paint_graph(%Dependency{clusters: clusters} = graph) do
    # 拓扑排序保证我们处理某节点时，它的上游都已经染色完毕
    sorted_nodes = Dependency.topological_sort(graph)

    Enum.reduce(sorted_nodes, %{}, fn node, color_map ->
      cond do
        explicit_color = Map.get(clusters.node_colors, node.name) ->
          Map.put(color_map, node.name, explicit_color)

        true ->
          upstream_colors = get_upstream_colors(node, graph, color_map)

          final_color = resolve_color(node, upstream_colors, clusters.mixing_strategy)
          Map.put(color_map, node.name, final_color)
      end
    end)
  end

  defp get_upstream_colors(%Node{name: name}, %Dependency{edges: edges}, color_map) do
    Enum.filter(edges, fn e -> e.to_node == name end)
    |> case do
      [] -> []
      _ = upper_edges -> Enum.map(upper_edges, fn e -> e.from_node end)
    end
    |> Enum.map(&Map.get(color_map, &1, :default_cluster))
  end

  defp resolve_color(_node, [], _), do: :default_cluster
  defp resolve_color(_node, [single_color], _), do: single_color

  defp resolve_color(node, _multiple_colors, :isolate),
    do: String.to_atom("#{node.name}_isolated_cluster")

  defp resolve_color(_node, _multiple_colors, {:merge_into, target_cluster}), do: target_cluster
end
