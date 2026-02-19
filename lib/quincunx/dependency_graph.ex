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

  # @spec compile([Node.t()], [Edge.t()]) :: %{input_ports: [InputPort.t()], output_ports: [OutputPort.t()], steps: any()}
end
