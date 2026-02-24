defmodule Quincunx.Dependency.Graph do
  alias Quincunx.Dependency.{Node, Edge, InputPort, OutputPort}

  # Generate by Gemini
  # not tested
  @spec compile([Node.t()], [Edge.t()]) :: %{
          input_ports: [InputPort.t()],
          output_ports: [OutputPort.t()],
          steps: [Orchid.Step.t()]
        }
  def compile(nodes, edges) do
    # 1. 建立 Edge 的快速查找表
    edges_to_inputs = Enum.group_by(edges, &{&1.to_node, &1.to_index})

    # 用于判断某个 Node 的 output 是否有被下游消费，没有则作为整个大图的 OutputPort
    edges_from_outputs = Enum.group_by(edges, &{&1.from_node, &1.from_index})

    # 2. 生成 Steps 并收集 ports
    compiled_data =
      Enum.reduce(nodes, %{steps: [], input_ports: [], output_ports: []}, fn node, acc ->
        if Node.orchid_step?(node) do
          {step, in_ports, out_ports} =
            solve_when_orchid_step(edges_to_inputs, edges_from_outputs, node)

          %{
            steps: [step | acc.steps],
            input_ports: in_ports ++ acc.input_ports,
            output_ports: out_ports ++ acc.output_ports
          }
        else
          {maybe_inputs, maybe_outputs} = solve_when_explicit_port(edges_to_inputs, node)

          %{
            acc
            | input_ports: maybe_inputs ++ acc.input_ports,
              output_ports: maybe_outputs ++ acc.output_ports
          }
        end
      end)

    %{
      # Add Enum.reverse/1 before
      input_ports: compiled_data.input_ports,
      output_ports: compiled_data.output_ports,
      steps: compiled_data.steps
    }
  end

  defp solve_when_orchid_step(edges_to_inputs, edges_from_outputs, node) do
    in_counts = count_ports(node.input_keys)
    out_counts = count_ports(node.output_keys)

    {in_keys, in_ports} =
      Enum.reduce(0..max(in_counts - 1, 0), {[], []}, fn idx, {keys, ports} ->
        case Map.get(edges_to_inputs, {node.name, idx}) do
          [edge | _] ->
            {[output_key_name(edge.from_node, edge.from_index) | keys], ports}

          nil ->
            port_key = input_key_name(node.name, idx)
            type = get_port_type(node.input_keys, idx)
            new_port = %InputPort{type: type, to_node: node, to_index: idx}
            {[port_key | keys], [new_port | ports]}
        end
      end)

    {out_keys, out_ports} =
      Enum.reduce(0..max(out_counts - 1, 0), {[], []}, fn idx, {keys, ports} ->
        node_out_key = output_key_name(node.name, idx)

        new_ports =
          if Map.has_key?(edges_from_outputs, {node.name, idx}) do
            # 有下游消费，不需要作为图的暴露输出
            ports
          else
            # 没有下游，图的隐式边界，暴露为 OutputPort
            type = get_port_type(node.output_keys, idx)
            [%OutputPort{type: type, from_node: node, from_index: idx} | ports]
          end

        {[node_out_key | keys], new_ports}
      end)

    step =
      {node.impl, format_keys(Enum.reverse(in_keys)), format_keys(Enum.reverse(out_keys)),
       node.step_opts}

    {step, in_ports, out_ports}
  end

  defp solve_when_explicit_port(edges_to_inputs, node) do
    # 判断它是图的 Input 还是 Output Node。
    # 简单启发式约定：如果有 output_keys，说明它能产生数据，是图的 Input 源点。
    # 如果有 input_keys，说明它要吸收数据，是图的 Output 汇点。

    is_source = count_ports(node.output_keys) > 0
    is_sink = count_ports(node.input_keys) > 0

    maybe_inputs =
      if is_source do
        # 作为图的输入点，它的 "输出 Key" 其实就是外部需要喂给大图的 "Input"
        new_in_ports =
          Enum.map(0..(count_ports(node.output_keys) - 1), fn idx ->
            type = get_port_type(node.output_keys, idx)

            # 注意这里虽然是 out_key 的名字，但在外层逻辑里这是全局注入的 Key
            # 为了保持 Orchid 的依赖链，它采用 output_key_name 的格式
            %InputPort{type: type, to_node: node, to_index: idx}
          end)

        new_in_ports
      else
        []
      end

    maybe_outputs =
      if is_sink do
        # 作为图的输出汇点，我们要沿着上游连线，把上游的结果暴露出去
        new_out_ports =
          Enum.reduce(0..(count_ports(node.input_keys) - 1), [], fn idx, ports ->
            case Map.get(edges_to_inputs, {node.name, idx}) do
              [edge | _] ->
                type = get_port_type(node.input_keys, idx)

                # 此处保存的是“从老节点出来的索引”，代表了结果的真实来源
                [
                  %OutputPort{
                    type: type,
                    from_node: edge.from_node,
                    from_index: edge.from_index
                  }
                  | ports
                ]

              nil ->
                # 空接的 OutputNode，忽略
                ports
            end
          end)

        new_out_ports
      else
        []
      end

    {maybe_inputs, maybe_outputs}
  end

  # --- 确定性的 Key 生成 ---
  # 这些命名规则确保了只要节点名称和索引不变，Orchid 承载数据的 key 就永远不变
  defp output_key_name(node_name, index), do: :"out_#{node_name}_#{index}"
  defp input_key_name(node_name, index), do: :"in_#{node_name}_#{index}"

  # --- 辅助方法 ---
  defp count_ports(nil), do: 0
  defp count_ports(tuple) when is_tuple(tuple), do: tuple_size(tuple)
  defp count_ports(list) when is_list(list), do: length(list)
  defp count_ports(_atom), do: 1

  defp get_port_type(tuple, idx) when is_tuple(tuple), do: elem(tuple, idx)
  defp get_port_type(list, idx) when is_list(list), do: Enum.at(list, idx)
  defp get_port_type(atom, 0), do: atom
  defp get_port_type(_, _), do: :any

  defp format_keys([]), do: []
  defp format_keys([key]), do: key
  defp format_keys(keys), do: keys
end
