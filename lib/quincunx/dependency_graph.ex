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
            from_node: Node.name(),
            to_node: Node.name(),
            type: Orchid.Param.param_type(),
            indicies: {from :: non_neg_integer(), to :: non_neg_integer()}
          }
    defstruct [:from_node, :to_node, :type, indicies: [0, 0]]
  end

  defmodule InputPort do
    defstruct [:type, :to_node, :to_index]
  end

  defmodule OutputPort do
    defstruct [:type, :from_node, :from_index]
  end

  @type t :: any()
  defstruct [:nodes, :edges]
  # {Node, Edge} => OrchidSteps & Ports(from_or_to, type) # ports is orphan port

  # def get_fields(=> required_inputs_fields and optional_input_fields)
end
