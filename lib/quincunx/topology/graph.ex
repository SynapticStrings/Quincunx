defmodule Quincunx.Topology.Graph do
  @moduledoc """
  The pure mathematical representation of the DAG.
  """

  defmodule Node do
    @moduledoc "A pure data representation of a computation step in the DAG."

    @type id :: atom() | String.t()

    @type node_port :: atom() | binary()

    @type t :: %__MODULE__{
            id: id(),
            impl: Orchid.Step.implementation(),
            inputs: [node_port()],
            outputs: [node_port()],
            opts: keyword(),
            extra: map()
          }

    defstruct [
      :id,
      :impl,
      inputs: [],
      outputs: [],
      opts: [],
      extra: %{}
    ]
  end

  defmodule Edge do
    @moduledoc """
    A directed edge representing data flow between two node ports.

    It also serves as the deterministic variable name across the larger system.
    """

    @type t :: %__MODULE__{
            from_node: Node.id(),
            from_port: Node.node_port(),
            to_node: Node.id(),
            to_port: Node.node_port()
          }

    defstruct [:from_node, :from_port, :to_node, :to_port]

    def new(from_node, from_port, to_node, to_port) do
      %__MODULE__{
        from_node: from_node,
        from_port: from_port,
        to_node: to_node,
        to_port: to_port
      }
    end
  end

  defmodule PortRef do
    @moduledoc "A container based on the node/port representation, used to dynamically generate Orchid keys."

    @type t :: {:port, node :: Node.id(), Node.node_port()}

    # This is actually a rather old design(Old orchid not support binary step io key),
    # but let's keep it for now.
    @spec to_orchid_key(t()) :: Orchid.Step.io_key()
    def to_orchid_key({:port, node, port}) do
      Atom.to_string(node) <> "_" <> parse_port(port)
    end

    defp parse_port(p) when is_binary(p), do: p
    defp parse_port(p) when is_atom(p), do: Atom.to_string(p)
  end

  # May add adjacency lists in future
  # (if graph is REALLY big)
  # in/out edge => %{Node.id() => [Edge.t()]}
  @type t :: %__MODULE__{
          nodes: %{Node.id() => Node.t()},
          edges: MapSet.t(Edge.t())
        }
  defstruct [:nodes, :edges]

  def new,
    do: %__MODULE__{
      nodes: %{},
      edges: MapSet.new()
    }

  # https://elixirforum.com/t/what-is-a-good-way-to-compare-structs/59303
  def same?(graph1, graph2), do: graph1 == graph2

  def add_node(%__MODULE__{nodes: old_nodes} = graph, %Node{id: node_id} = node) do
    %{graph | nodes: Map.put(old_nodes, node_id, node)}
  end

  def remove_node(%__MODULE__{nodes: nodes, edges: edges}, node_id) do
    case nodes[node_id] do
      nil ->
        %__MODULE__{nodes: nodes, edges: edges}

      _ ->
        %__MODULE__{
          nodes: Map.delete(nodes, node_id),
          edges:
            edges
            |> Enum.reject(&(&1.from_node == node_id or &1.to_node == node_id))
            |> Enum.into(%MapSet{})
        }
    end
  end

  def update_node(%__MODULE__{nodes: nodes} = graph, node_id, new_node) do
    case nodes[node_id] do
      nil ->
        graph

      old_node = %Node{} ->
        %{
          graph
          | nodes: %{
              nodes
              | node_id =>
                  case new_node do
                    new_node when is_function(new_node, 1) -> new_node.(old_node)
                    _ -> new_node
                  end
            }
        }
    end
  end

  def add_edge(%__MODULE__{} = graph, edge) do
    %{graph | edges: MapSet.put(graph.edges, edge)}
  end

  def remove_edge(%__MODULE__{edges: edges} = graph, edge) do
    %{graph | edges: MapSet.delete(edges, edge)}
  end

  @doc "Get all input edges pointing to a given node"
  @spec get_in_edges(t(), Node.id()) :: [Edge.t()]
  def get_in_edges(%__MODULE__{} = graph, node_id) do
    Enum.filter(graph.edges, &(&1.to_node == node_id))
  end

  @doc "Get all output edges emanating from a given node."
  @spec get_out_edges(t(), Node.id()) :: [Edge.t()]
  def get_out_edges(%__MODULE__{} = graph, node_id) do
    Enum.filter(graph.edges, &(&1.from_node == node_id))
  end

  @spec topological_sort(t()) :: {:ok, [Node.id()]} | {:error, :cycle_detected}
  def topological_sort(%__MODULE__{} = graph) do
    init_in_degrees = Map.keys(graph.nodes) |> Map.new(fn id -> {id, 0} end)

    in_degrees =
      Enum.reduce(graph.edges, init_in_degrees, fn edge, acc ->
        Map.update!(acc, edge.to_node, &(&1 + 1))
      end)

    adj_list = Enum.group_by(graph.edges, & &1.from_node, & &1.to_node)

    zero_in_degree_nodes =
      in_degrees
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _degree} -> id end)

    do_topo_sort(zero_in_degree_nodes, in_degrees, adj_list, map_size(graph.nodes), [])
  end

  defp do_topo_sort([], _in_degrees, _adj_list, total_nodes, sorted_acc) do
    if length(sorted_acc) == total_nodes do
      {:ok, Enum.reverse(sorted_acc)}
    else
      {:error, :cycle_detected}
    end
  end

  defp do_topo_sort([node_id | rest_zero_nodes], in_degrees, adj_list, total, sorted_acc) do
    neighbors = Map.get(adj_list, node_id, [])

    {new_in_degrees, new_zero_nodes} =
      Enum.reduce(neighbors, {in_degrees, rest_zero_nodes}, fn to_node, {deg_acc, zero_acc} ->
        new_deg = deg_acc[to_node] - 1
        deg_acc = Map.put(deg_acc, to_node, new_deg)

        case new_deg do
          0 -> {deg_acc, [to_node | zero_acc]}
          _ -> {deg_acc, zero_acc}
        end
      end)

    do_topo_sort(new_zero_nodes, new_in_degrees, adj_list, total, [node_id | sorted_acc])
  end
end
