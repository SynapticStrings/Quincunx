defmodule QuincunxTest.GraphFactory do
  alias Quincunx.Topology.{Graph, Graph.Node, Graph.Edge}

  def build_graph_v1 do
    Graph.new()
    |> Graph.add_node(%Node{
      id: :node_a,
      impl: fn _, _ -> {:ok, Orchid.Param.new(:mid1, :any)} end,
      inputs: [:in],
      outputs: [:mid]
    })
    |> Graph.add_node(%Node{
      id: :node_b,
      impl: fn _, _ -> {:ok, Orchid.Param.new(:out, :any)} end,
      inputs: [:mid],
      outputs: [:out]
    })
    |> Graph.add_edge(Edge.new(:node_a, :mid, :node_b, :mid))
  end
end
