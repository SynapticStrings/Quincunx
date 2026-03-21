defmodule LilyGraphChangeTest do
  use ExUnit.Case

  # focus on
  alias Quincunx.Lily.Graph
  alias Quincunx.Lily.Graph.{Node, Edge}
  # and
  alias Quincunx.Lily.History

  def init do
    dummy_step1 = fn %Orchid.Param{payload: inputs}, _ ->
      {:ok, %Orchid.Param{payload: inputs <> "-> DummyStep1"}}
    end

    dummy_step2 = fn %Orchid.Param{payload: inputs}, _ ->
      {:ok, %Orchid.Param{payload: inputs <> "-> DummyStep2"}}
    end

    dummy_step3 = fn [%Orchid.Param{payload: i1}, %Orchid.Param{payload: i2}], _ ->
      {:ok, %Orchid.Param{payload: "DummyStep3(#{i1}, #{i2})"}}
    end

    dummy_step4 = fn %Orchid.Param{payload: inputs}, _ ->
      {:ok,
       [
         %Orchid.Param{payload: "DummyStep4(#{inputs}_1)"},
         %Orchid.Param{payload: "DummyStep4(#{inputs}_2)"}
       ]}
    end

    init_nodes = [
      %Node{id: :_1, impl: dummy_step1, inputs: [:in], outputs: [:out1]},
      %Node{id: :_2, impl: dummy_step2, inputs: [:in], outputs: [:out2]},
      %Node{id: :_3, impl: dummy_step3, inputs: [:op1, :op2], outputs: [:out3]},
      %Node{id: :_4, impl: dummy_step4, inputs: [:in], outputs: [:o1, :o2]}
    ]

    Enum.reduce(init_nodes, Graph.new(), &Graph.add_node(&2, &1))
  end

  test "do, undo & redo" do
    records =
      [
        {:add_edge, %Edge{from_node: :_1, to_node: :_3, from_port: :out1, to_port: :op1}},
        {:add_edge, %Edge{from_node: :_2, to_node: :_3, from_port: :out2, to_port: :op2}},
        {:add_edge, %Edge{from_node: :_3, to_node: :_4, from_port: :out3, to_port: :in}},
        {:add_node,
         %Node{id: :shadow1, impl: fn i, _ -> {:ok, i} end, inputs: [:in], outputs: [:out]}},
        {:add_node,
         %Node{id: :shadow2, impl: fn i, _ -> {:ok, i} end, inputs: [:in], outputs: [:out]}},
        {:add_edge, %Edge{from_node: :_4, to_node: :shadow1, from_port: :o1, to_port: :in}},
        {:add_edge, %Edge{from_node: :_4, to_node: :shadow2, from_port: :o2, to_port: :in}},
        {:remove_node, :shadow2},
        {:remove_edge, %Edge{from_node: :_4, to_node: :shadow2, from_port: :o2, to_port: :in}},
        {:update_node, :shadow1,
         %Node{
           id: :shadow1,
           impl: fn %Orchid.Param{payload: p}, _ ->
             {:ok, %Orchid.Param{payload: "ShadowStep(#{p})"}}
           end,
           inputs: [:in],
           outputs: [:out]
         }},
        {:set_input, {:port, :_1, :in}, "In1"},
        {:set_input, {:port, :_2, :in}, "In1"},
        {:remove_input, {:port, :_2, :in}},
        {:set_input, {:port, :_2, :in}, "In2"}
      ]

    history =
      Enum.reduce(records, History.new(), &History.push(&2, &1))
      |> History.undo()
      |> History.redo()

    {graph, _offset} = History.resolve(init(), history)

    assert [_, _] = Graph.get_in_edges(graph, :_3)
    assert [_] = Graph.get_in_edges(graph, :_4)

    Enum.reduce(
      records,
      Quincunx.Session.Segment.new(:test, graph),
      &Quincunx.Session.Segment.apply_operation(&2, &1)
    )
    |> Quincunx.Session.Segment.compile_to_recipes()
    |> elem(1)
    # |> List.wrap()
    # |> Enum.map(fn seg ->
    #   Enum.map(seg.compiled_recipes, &{seg.id, &1})
    # end)
    # |> Enum.zip()
    # |> Enum.map(&Tuple.to_list/1)
    # |> Enum.at(0)
    # |> Enum.at(0)
    # |> elem(1)
    |> IO.inspect()
  end

  test "blank history" do
    history =
      History.new()
      |> History.undo()
      |> History.redo()

    assert history.redo_stack == []
    assert history.undo_stack == []
  end
end
