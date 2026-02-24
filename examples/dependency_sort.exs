alias Quincunx.Dependency.{Node, Edge, Cluster}

nodes = [
  %Node{
    name: :split,
    impl: fn %Orchid.Param{payload: p}, _ ->
      {:ok,
       [
         %Orchid.Param{name: :split_1, payload: p, type: :number},
         %Orchid.Param{name: :split_1, payload: p, type: :number}
       ]}
    end,
    input_keys: [:number],
    output_keys: [:number, :number],
    step_opts: []
  },
  %Node{
    name: :add,
    impl: fn [%Orchid.Param{payload: a}, %Orchid.Param{payload: b}], _ ->
      {:ok,
       [
         %Orchid.Param{name: :add_res, payload: a + b, type: :number}
       ]}
    end,
    input_keys: [:number, :number],
    output_keys: [:number],
    step_opts: []
  },
  %Node{
    name: :mul,
    impl: fn [%Orchid.Param{payload: a}, %Orchid.Param{payload: b}], _ ->
      {:ok,
       [
         %Orchid.Param{name: :mul_res, payload: a * b, type: :number}
       ]}
    end,
    input_keys: [:number, :number],
    output_keys: [:number],
    step_opts: []
  },
  %Node{
    name: :inc,
    impl: fn %Orchid.Param{payload: a}, _ ->
      {:ok,
       [
         %Orchid.Param{name: :inc_res, payload: a + 1, type: :number}
       ]}
    end,
    input_keys: [:number],
    output_keys: [:number],
    step_opts: []
  },
  %Node{
    name: :dec,
    impl: fn %Orchid.Param{payload: a}, _ ->
      {:ok,
       [
         %Orchid.Param{name: :inc_res, payload: a - 1, type: :number}
       ]}
    end,
    input_keys: [:number],
    output_keys: [:number],
    step_opts: []
  }
]

edges = [
  %Edge{
    type: :number,
    from_node: :split,
    from_index: 0,
    to_node: :inc,
    to_index: 0
  },
  %Edge{},
  %Edge{},
  %Edge{},
  %Edge{}
]
