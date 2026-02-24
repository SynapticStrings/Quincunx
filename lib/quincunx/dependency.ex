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

  def topological_sort(%__MODULE__{nodes: _nodes, edges: _edges}) do
    []
  end
end
