defmodule Quincunx.Dependency do
  defmodule Node do
    @type name :: atom() | binary()
    @type keys_type_declare :: Orchid.Param.param_type() | [Orchid.Param.param_type()] | tuple()
    @type quincunx_node_options :: keyword()

    @type t :: %__MODULE__{
            name: name(),
            impl: Orchid.Step.implementation() | any(),
            input_keys: keys_type_declare(),
            output_keys: keys_type_declare(),
            step_opts: Orchid.Step.step_options(),
            node_opts: quincunx_node_options(),
            extra: %{}
          }
    defstruct [:name, :impl, :input_keys, :output_keys, :step_opts, :node_opts, :extra]

    def orchid_step?(%__MODULE__{} = node) when is_function(node.impl, 2), do: true

    def orchid_step?(%__MODULE__{} = node) when is_atom(node.impl),
      do:
        if(Code.ensure_loaded?(node.impl) and function_exported?(node.impl, :run, 2),
          do: true,
          else: false
        )

    def orchid_step?(%__MODULE__{}), do: false
  end

  defmodule Edge do
    @type t :: %__MODULE__{
            type: Orchid.Param.param_type(),
            from_node: Node.name(),
            to_node: Node.name(),
            from_index: non_neg_integer(),
            to_index: non_neg_integer()
          }
    defstruct [:type, :from_node, :to_node, from_index: 0, to_index: 0]
  end

  defmodule InputPort do
    @type t :: %__MODULE__{
            type: Orchid.Param.param_type(),
            to_node: Node.t(),
            to_index: non_neg_integer()
          }
    defstruct [:type, :to_node, :to_index]
  end

  defmodule OutputPort do
    @type t :: %__MODULE__{
            type: Orchid.Param.param_type(),
            from_node: Node.t(),
            from_index: non_neg_integer()
          }
    defstruct [:type, :from_node, :from_index]
  end

  @type t :: %__MODULE__{
          nodes: [Node.t()],
          edges: [Edge.t()],
          clusters: Quincunx.Dependency.Cluster.t()
        }
  defstruct [:nodes, :edges, :clusters]

  @spec topological_sort(t()) :: {:ok, [Node.t()]} | {:error, :cycle_detected}
  def topological_sort(%__MODULE__{nodes: nodes, edges: edges}) do
    # 1. 建立以名称为键的节点 Map，方便最终组装返回 [Node.t()]
    node_map = Map.new(nodes, fn node -> {node.name, node} end)
    node_names = Map.keys(node_map)

    # 2. 初始化邻接表 (Adjacency List) 和入度表 (In-degree Map)
    # 保证即使是孤立节点也在图结构中
    initial_adj = Map.new(node_names, fn name -> {name, []} end)
    initial_indegree = Map.new(node_names, fn name -> {name, 0} end)

    # 3. 遍历边，填充图结构
    {adj, indegree} =
      Enum.reduce(edges, {initial_adj, initial_indegree}, fn edge, {a_acc, i_acc} ->
        from = edge.from_node
        to = edge.to_node

        # 为了避免边引用了不存在的节点，做一次基础校验
        if Map.has_key?(a_acc, from) and Map.has_key?(i_acc, to) do
          new_a_acc = Map.update!(a_acc, from, fn neighbors -> [to | neighbors] end)
          new_i_acc = Map.update!(i_acc, to, fn deg -> deg + 1 end)
          {new_a_acc, new_i_acc}
        else
          {a_acc, i_acc}
        end
      end)

    # 4. 获取所有初始入度为 0 的节点作为起始队列
    queue =
      indegree
      |> Enum.filter(fn {_name, deg} -> deg == 0 end)
      |> Enum.map(fn {name, _deg} -> name end)

    # 5. 执行 Kahn 算法的递归处理
    sorted_names = do_kahn(queue, adj, indegree, [])

    # 6. 验证并返回结果 (检查是否有环)
    if length(sorted_names) == length(nodes) do
      # 映射回 Node.t() 结构体
      sorted_nodes = Enum.map(sorted_names, fn name -> Map.fetch!(node_map, name) end)
      {:ok, sorted_nodes}
    else
      {:error, :cycle_detected}
    end
  end

  # --- 私有辅助函数：Kahn 算法的具体执行 ---

  # 队列为空，递归结束。结果需要 reverse，因为我们是往列表头部追加(tail-recursive)
  defp do_kahn([], _adj, _indegree, result_acc) do
    Enum.reverse(result_acc)
  end

  # 取出队列头部节点 current，更新其邻居的入度
  defp do_kahn([current | rest_queue], adj, indegree, result_acc) do
    neighbors = Map.get(adj, current, [])

    # 遍历所有邻居，将其入度减 1。如果降为 0，则加入队列
    {new_queue, new_indegree} =
      Enum.reduce(neighbors, {rest_queue, indegree}, fn neighbor, {q_acc, in_acc} ->
        new_deg = in_acc[neighbor] - 1
        updated_in_acc = Map.put(in_acc, neighbor, new_deg)

        if new_deg == 0 do
          {[neighbor | q_acc], updated_in_acc}
        else
          {q_acc, updated_in_acc}
        end
      end)

    # 继续处理下一个
    do_kahn(new_queue, adj, new_indegree, [current | result_acc])
  end
end
