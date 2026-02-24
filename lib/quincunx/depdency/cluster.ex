defmodule Quincunx.Dependency.Cluster do
  # 将依赖依照用户选择以及依赖关系分簇
  # 以实现并行控制
  # 人话：将部分很耗费资源的服务单独丢出去
  # 将整个并行改成串行 + 并行
  alias Quincunx.Dependency
  alias Quincunx.Dependency.Node
  @type cluster_name :: atom() | String.t()

  @type t :: %__MODULE__{
          node_colors: %{Node.name() => cluster_name()},
          merge_groups: [{[cluster_name()] | MapSet.t(cluster_name()), cluster_name()}]
        }
  defstruct node_colors: %{},
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
          Map.put(color_map, node.name, get_upstream_colors(node, graph, color_map))
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
    # [[:foo, :bar], :bar] => [:foo, :bar]
    |> List.flatten()
    |> Enum.uniq()
  end
end
