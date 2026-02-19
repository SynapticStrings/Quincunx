defmodule Quincunx.DependencyGraph do
  defmodule Node do
    @type name :: atom() | binary()
    @type keys_type_declare :: Orchid.Param.param_type() | [Orchid.Param.param_type()] | tuple()
    @type quincunx_node_options :: keyword()

    @type t :: %__MODULE__{
            name: name(),
            impl: Orchid.Step.implementation(),
            input_keys: keys_type_declare(),
            output_keys: keys_type_declare(),
            step_opts: Orchid.Step.step_options(),
            node_opts: quincunx_node_options(),
            extra: %{}
          }
    defstruct [:name, :impl, :input_keys, :output_keys, :step_opts, :node_opts, :extra]
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

  @type t :: any()

  @spec compile([Node.t()], [Edge.t()]) :: %{
          input_ports: [InputPort.t()],
          output_ports: [OutputPort.t()],
          steps: [Orchid.Step.t()]
        }
  def compile(nodes, edges) do
    # 1. 将 Edge 转换为以 {to_node_name, to_index} 为 Key 的 Map，方便查找输入源
    incoming_map =
      Map.new(edges, fn %Edge{to_node: tn, to_index: ti} = e ->
        {{tn, ti}, e}
      end)

    # 2. 遍历所有节点，构建所需数据结构
    # Acc 结构: %{steps: [], input_ports: [], output_ports: []}
    result =
      Enum.reduce(nodes, %{steps: [], input_ports: [], output_ports: []}, fn node, acc ->
        # 处理输入侧
        {input_keys_atoms, new_input_ports} = resolve_inputs(node, incoming_map)

        # 处理输出侧
        {output_keys_atoms, new_output_ports} = resolve_outputs(node)

        # 构建 Orchid Step
        step = {node.impl, input_keys_atoms, output_keys_atoms, node.step_opts || []}

        %{
          steps: [step | acc.steps],
          input_ports: new_input_ports ++ acc.input_ports,
          output_ports: new_output_ports ++ acc.output_ports
        }
      end)

    # 3. 整理结果（步骤通常保持输入顺序或为了确定性反转回来，虽然 Orchid 会自动拓扑排序）
    %{
      input_ports: Enum.reverse(result.input_ports),
      output_ports: Enum.reverse(result.output_ports),
      # Orchid 实际上不依赖 steps 列表的顺序，但保持处理顺序便于调试
      steps: Enum.reverse(result.steps)
    }
  end

  # ==========================================
  # 私有辅助函数
  # ==========================================

  # 解析输入：确定每一个 Input Slot 对应的变量名
  # 如果有边连接 -> 使用上游节点的输出变量名
  # 如果无边连接 -> 生成全局输入变量名，并创建 InputPort
  defp resolve_inputs(node, incoming_map) do
    {types, is_list} = normalize_type_declare(node.input_keys)

    {keys, ports} =
      types
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {type, index}, {k_acc, p_acc} ->
        case Map.get(incoming_map, {node.name, index}) do
          # Case A: 存在传入边，使用中间变量名 (Internal Link)
          %Edge{from_node: from_node, from_index: from_index} ->
            var_name = generate_link_key(from_node, from_index)
            {[var_name | k_acc], p_acc}

          # Case B: 没有边，视为全局输入 (Graph Input)
          nil ->
            var_name = generate_input_key(node.name, index)
            port = %InputPort{type: type, to_node: node, to_index: index}
            {[var_name | k_acc], [port | p_acc]}
        end
      end)

    # 如果原定义不是列表（单原子），需要解包 step 的 keys 定义
    final_keys = if is_list, do: Enum.reverse(keys), else: List.first(keys)
    {final_keys, Enum.reverse(ports)}
  end

  # 解析输出：为每一个 Output Slot 生成变量名，并创建 OutputPort
  defp resolve_outputs(node) do
    {types, is_list} = normalize_type_declare(node.output_keys)

    {keys, ports} =
      types
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {type, index}, {k_acc, p_acc} ->
        # 即使该输出没有被下游使用，它仍然是该节点的产出，Orchid 执行后会包含此 Key
        var_name = generate_link_key(node.name, index)
        port = %OutputPort{type: type, from_node: node, from_index: index}
        {[var_name | k_acc], [port | p_acc]}
      end)

    final_keys = if is_list, do: Enum.reverse(keys), else: List.first(keys)
    {final_keys, Enum.reverse(ports)}
  end

  # 标准化类型声明：
  # Orchid 允许 input_keys 为 atom (单参) 或 list (多参)
  # 这里我们需要知道具体的参数个数 (arity) 以及每个参数的类型
  # 返回: {[Type], is_list_structure?}
  defp normalize_type_declare(decl) when is_list(decl), do: {decl, true}
  # 处理 tuple 形式，通常视为多参数列表
  defp normalize_type_declare(decl) when is_tuple(decl), do: {Tuple.to_list(decl), true}
  # 单个 atom，视为单参数
  defp normalize_type_declare(decl), do: {[decl], false}

  # 生成变量名规则
  # 这是连接 Graph logic 和 Orchid logic 的桥梁

  # 输出节点的变量名 (也是下游的输入变量名)
  # 格式: :"nodeName_out_index"
  defp generate_link_key(node_name, index) do
    :"#{node_name}_out_#{index}"
  end

  # 全局输入变量名
  # 格式: :"in_nodeName_index"
  defp generate_input_key(node_name, index) do
    :"in_#{node_name}_#{index}"
  end
end
