# 🌸Lily

**The pure functional DAG and compilation core.**

Lily handles the mathematical topology, user edit history, and execution plan generation for interactive editors. It delegates all side-effects and hardware scheduling to its host engine.

## 🎯 Philosophy

*   **Pure Data:** No GenServers, no ETS, zero side-effects.
*   **Time Travel:** O(1) Undo/Redo with zero memory copying.
*   **Deterministic:** Compiles user interventions and topological splits into strictly consistent `Orchid.Recipe`s.

## 🏗️ Architecture

1.  **`Lily.Graph`**: A strict, port-centric DAG. Connections and variables are defined by immutable keys (`{:port, node_id, port_name}`).
2.  **`Lily.History`**: A double-stack event sourcer. It folds chronological operations (node mutations, data overrides) into a single `effective_state`.
3.  **`Lily.Compiler`**: The translator. It partitions the graph into clusters (e.g., splitting heavy GPU nodes from CPU nodes), bridges cut edges via `requires/exports`, and maps user overrides into Orchid's execution baggage.

## 🚀 Quick Start

```elixir
alias Lily.{Graph, Graph.Node, Graph.Edge, Graph.Cluster, History, Compiler}

# 1. Build the static topology
graph = Graph.new()
|> Graph.add_node(%Node{id: :acoustic, impl: Acostic, inputs: [:lyrics], outputs: [:mel]})
|> Graph.add_node(%Node{id: :vocoder, impl: Vocoder,  inputs: [:mel], outputs: [:audio]})
|> Graph.add_edge(Edge.new(:acoustic, :mel, :vocoder, :mel))

# 2. Record user interventions (e.g., overriding AI tensors via UI)
history = History.new()
|> History.push({:override, {:port, :vocoder, :mel}, <<0, 1, "tensor_data">>})

# 3. Fold history into the current effective state
state = History.resolve(graph, history)

# 4. Compile & Partition (Split execution to prevent VRAM overflow)
clusters = %Cluster{node_colors: %{acoustic: :gpu_1, vocoder: :gpu_2}}
{:ok, [recipe_1, recipe_2]} = Compiler.compile(state, clusters)
# => recipe_1
%{
  exports: [:acoustic_mel],
  requires: [:acoustic_lyrics],
  overrides: %{},
  offsets: %{},
  recipe: %Orchid.Recipe{
    steps: [{Acostic, [:acoustic_lyrics], [:acoustic_mel], []}],
    name: :gpu_1,
    opts: []
  }
}
# => recipe_2
%{
  exports: [],
  requires: [:acoustic_mel],
  overrides: %{
    {:port, :vocoder, :mel} => <<0, 1, 116, 101, 110, 115, 111, 114, 95, 100,
      97, 116, 97>>
  },
  offsets: %{},
  recipe: %Orchid.Recipe{
    steps: [{Vocoder, [:acoustic_mel], [:vocoder_audio], []}],
    name: :gpu_2,
    opts: []
  }
}
```

---

## Source Code

```elixir
defmodule Lily.MixProject do
  use Mix.Project

  def project do
    [
      app: :lily,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:orchid, "~> 0.5"}
    ]
  end
end


defmodule Lily do
  @moduledoc """
  Documentation for `Lily`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Lily.hello()
      :world

  """
  def hello do
    :world
  end
end

defmodule Lily.Compiler do
  @moduledoc """
  The final stage of the Lily pure functional pipeline.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Lily.Graph
  alias Lily.Graph.{Node, Portkey, Cluster}

  @type port_key_name :: {:port, target_node :: Node.id(), target_port :: atom()}

  @doc """
  将有效状态和分簇策略编译为 Recipe 序列。
  """
  def compile(
        %{graph: graph, overrides: global_overrides, offsets: global_offsets},
        cluster_declara \\ %Cluster{}
      ) do
    # 1. 确保图是合法的，并拿到拓扑执行顺序
    case Graph.topological_sort(graph) do
      {:error, _} = err ->
        err

      {:ok, sorted_node_ids} ->
        # 2. 染色：决定每个 Node 属于哪个 Cluster
        node_colors =
          Lily.Graph.Cluster.paint_graph(sorted_node_ids, graph.edges, cluster_declara)

        # 3. 按簇分组
        clusters =
          Enum.group_by(
            # 保持拓扑顺序
            sorted_node_ids,
            fn id -> Map.get(node_colors, id, :default_cluster) end
          )

        # 4. 生成 Orchid Recipe
        recipes =
          Enum.map(clusters, fn {cluster_name, node_ids_in_cluster} ->
            build_recipe(cluster_name, node_ids_in_cluster, graph, %{
              overrides: global_overrides,
              offsets: global_offsets
            })
          end)

        {:ok, recipes}
    end
  end

  defp build_recipe(cluster_name, node_ids, graph, %{
         overrides: global_overrides,
         offsets: global_offsets
       }) do
    steps =
      node_ids
      |> Enum.map(&Map.fetch!(graph.nodes, &1))
      |> Enum.map(&node_to_step(&1, graph))

    {requires, exports} = calculate_boundaries(node_ids, graph)

    overrides =
      global_overrides
      |> Enum.filter(fn {{:port, target_node, _port}, _data} ->
        target_node in node_ids
      end)
      |> Enum.into(%{})

    offsets =
      global_offsets
      |> Enum.filter(fn {{:port, target_node, _port}, _data} ->
        target_node in node_ids
      end)
      |> Enum.into(%{})

    %{
      recipe: Orchid.Recipe.new(steps, name: cluster_name),
      requires: requires,
      exports: exports,
      overrides: overrides,
      offsets: offsets
    }
  end

  defp node_to_step(%Node{} = node, graph) do
    in_edges = Graph.get_in_edges(graph, node.id)

    step_inputs =
      Enum.map(node.inputs, fn port_name ->
        case Enum.find(in_edges, &(&1.to_port == port_name)) do
          nil -> Portkey.to_orchid_key({:port, node.id, port_name})
          edge -> Portkey.to_orchid_key({:port, edge.from_node, edge.from_port})
        end
      end)

    step_outputs =
      Enum.map(node.outputs, fn port_name ->
        Portkey.to_orchid_key({:port, node.id, port_name})
      end)

    build_orchid_step(
      node.impl,
      step_inputs,
      step_outputs,
      node.opts
    )
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    # 1. 计算 Requires:
    # a. 来自外部簇的输入边
    external_in_edges =
      graph.edges
      |> Enum.filter(fn e ->
        e.to_node in cluster_nodes_set and e.from_node not in cluster_nodes_set
      end)
      |> Enum.map(fn e -> Portkey.to_orchid_key({:port, e.from_node, e.from_port}) end)

    # b. 完全没有连线的悬空输入 (Dangling Inputs)
    dangling_inputs =
      Enum.flat_map(node_ids_in_cluster, fn node_id ->
        node = graph.nodes[node_id]
        in_edges = Graph.get_in_edges(graph, node_id)

        node.inputs
        |> Enum.reject(fn port -> Enum.any?(in_edges, &(&1.to_port == port)) end)
        |> Enum.map(fn port -> Portkey.to_orchid_key({:port, node.id, port}) end)
      end)

    requires = Enum.uniq(external_in_edges ++ dangling_inputs)

    # 2. 计算 Exports:
    # 流向外部簇的输出边
    exports =
      graph.edges
      |> Enum.filter(fn e ->
        e.from_node in cluster_nodes_set and e.to_node not in cluster_nodes_set
      end)
      |> Enum.map(fn e -> Portkey.to_orchid_key({:port, e.from_node, e.from_port}) end)
      |> Enum.uniq()

    {requires, exports}
  end

  def build_orchid_step(impl, inputs, outputs, opts) do
    {impl, inputs, outputs, opts}
  end
end

defmodule Lily.Graph do
  @moduledoc """
  The pure mathematical representation of the DAG.
  """

  defmodule Node do
    @moduledoc "A pure data representation of a computation step in the DAG."

    @type id :: atom() | String.t()

    @type t :: %__MODULE__{
            id: id(),
            impl: Orchid.Step.implementation(),
            inputs: [atom()],
            outputs: [atom()],
            opts: keyword(),
            maybe_input_context: %{atom() => any()},
            extra: map()
          }

    defstruct [
      :id,
      :impl,
      inputs: [],
      outputs: [],
      opts: [],
      maybe_input_context: nil,
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
            from_port: atom(),
            to_node: Node.id(),
            to_port: atom()
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

    @spec to_edge_key(t()) :: Lily.History.Operation.edge_key()
    def to_edge_key(%__MODULE__{} = edge) do
      {:edge, edge.from_node, edge.from_port, edge.to_node, edge.to_port}
    end
  end

  defmodule Portkey do
    @type t :: {:port, node :: Node.id(), port :: atom()}

    @spec to_orchid_key(t()) :: atom()
    def to_orchid_key({:port, node, port}) do
      :"#{node}_#{port}"
    end
  end

  @type t :: %__MODULE__{
          nodes: %{Node.id() => Node.t()} | %{},
          edges: MapSet.t(Edge.t()) | MapSet.t()
        }

  defstruct nodes: %{}, edges: MapSet.new()

  def new, do: %__MODULE__{}

  @spec add_node(t(), Node.t()) :: t()
  def add_node(%__MODULE__{nodes: old_nodes} = graph, %Node{id: node_id} = node) do
    %{graph | nodes: Map.put(old_nodes, node_id, node)}
  end

  @spec remove_node(t(), Node.id()) :: t()
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

  @spec update_node(t(), Node.id(), new_node :: Node.t()) :: t()
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

  @spec add_edge(t(), Edge.t()) :: t()
  def add_edge(%__MODULE__{} = graph, edge) do
    %{graph | edges: MapSet.put(graph.edges, edge)}
  end

  @spec remove_edge(t(), Edge.t()) :: t()
  def remove_edge(%__MODULE__{edges: edges} = graph, edge) do
    %{
      graph
      | edges:
          edges
          |> Enum.reject(&(&1 == edge))
          |> Enum.into(%MapSet{})
    }
  end

  @doc "获取指向某节点的所有输入边"
  @spec get_in_edges(t(), Node.t()) :: [Edge.t()]
  def get_in_edges(%__MODULE__{} = graph, node_id) do
    Enum.filter(graph.edges, &(&1.to_node == node_id))
  end

  @doc "获取从某节点发出的所有输出边"
  @spec get_out_edges(t(), Node.t()) :: [Edge.t()]
  def get_out_edges(%__MODULE__{} = graph, node_id) do
    Enum.filter(graph.edges, &(&1.from_node == node_id))
  end

  @spec topological_sort(t()) :: {:ok, [Node.id()]} | {:error, :cycle_detected}
  def topological_sort(%__MODULE__{} = graph) do
    # 1. 初始化所有节点的入度 (In-degree) 为 0
    init_in_degrees = Map.keys(graph.nodes) |> Map.new(fn id -> {id, 0} end) |> Enum.into(%{})

    # 2. 遍历所有边，计算每个节点的真实入度
    in_degrees =
      Enum.reduce(graph.edges, init_in_degrees, fn edge, acc ->
        Map.update!(acc, edge.to_node, &(&1 + 1))
      end)

    # 3. 找出所有入度为 0 的游离节点（图的起始触发点）
    zero_in_degree_nodes =
      in_degrees
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(fn {id, _degree} -> id end)

    # 4. 开始递归剥离图
    do_topo_sort(zero_in_degree_nodes, in_degrees, graph, [])
  end

  # Kahn 算法的核心递归
  defp do_topo_sort([], _in_degrees, graph, sorted_acc) do
    # 如果已排序的节点数量等于图中的总节点数，说明排序成功
    if length(sorted_acc) == map_size(graph.nodes) do
      {:ok, Enum.reverse(sorted_acc)}
    else
      # 还有节点没被剥离，说明它们互相依赖，形成了死锁（环）！
      {:error, :cycle_detected}
    end
  end

  defp do_topo_sort([node_id | rest_zero_nodes], in_degrees, graph, sorted_acc) do
    # 遍历入度为 0 的边，将它们指向的下游节点的入度减 1
    {new_in_degrees, new_zero_nodes} =
      graph.edges
      |> Enum.filter(&(&1.from_node == node_id))
      |> Enum.reduce({in_degrees, rest_zero_nodes}, fn edge, {deg_acc, zero_acc} ->
        new_deg = deg_acc[edge.to_node] - 1
        deg_acc = Map.put(deg_acc, edge.to_node, new_deg)

        # 如果下游节点的入度变成了 0，将其加入下一轮待处理队列
        case new_deg do
          0 -> {deg_acc, [edge.to_node | zero_acc]}
          _ -> {deg_acc, zero_acc}
        end
      end)

    # 递归处理下一批入度为 0 的节点
    do_topo_sort(new_zero_nodes, new_in_degrees, graph, [node_id | sorted_acc])
  end
end

defmodule Lily.Graph.Cluster do
  # 将依赖依照用户选择以及依赖关系分簇
  # 以实现并行控制
  # 人话：将部分很耗费资源的服务单独丢出去
  # 将整个并行改成串行 + 并行
  alias Lily.Graph.{Node, Edge}

  @type cluster_name :: atom() | String.t() | [cluster_name()]

  @type t :: %__MODULE__{
          node_colors: %{Node.id() => cluster_name()},
          merge_groups: [{cluster_name() | MapSet.t(cluster_name()), cluster_name()}]
        }
  defstruct node_colors: %{},
            merge_groups: []

  @spec paint_graph([Node.t()], MapSet.t(Edge.t()), Lily.Graph.Cluster.t()) ::
          %{Node.id() => cluster_name()}
  @doc "Return `%{node_name => final_cluster_name}`"
  def paint_graph(sorted_nodes, edges, %__MODULE__{} = clusters) do
    Enum.reduce(sorted_nodes, %{}, fn node_id, color_map ->
      cond do
        explicit_color = Map.get(clusters.node_colors, node_id) ->
          Map.put(color_map, node_id, explicit_color)

        true ->
          Map.put(color_map, node_id, get_upstream_colors(node_id, edges, color_map))
      end
    end)
    # normalize clusters
    |> Enum.map(fn {k, v} -> {k, case v do v when is_list(v) -> Enum.sort(v); v -> v end} end)
    |> Enum.into(%{})
  end

  defp get_upstream_colors(node_id, edges, color_map) do
    Enum.filter(edges, fn e -> e.to_node == node_id end)
    |> case do
      [] -> []
      _ = upper_edges -> Enum.map(upper_edges, fn e -> e.from_node end)
    end
    |> Enum.map(&Map.get(color_map, &1, :default_cluster))
    # [[:foo, :bar], :bar] => [:foo, :bar]
    |> List.flatten()
    |> Enum.uniq()
  end
end

defmodule Lily.History do
  defmodule Operation do
    alias Lily.Graph.{Node, Edge, Portkey}

    @type edge_key ::
            {:edge, from_node :: atom(), from_port :: atom(), to_node :: atom(),
             to_port :: atom()}

    @type topology_mutation ::
            {:add_node, Node.t()}
            | {:update_node, Node.id(),
               node_or_update_funtion :: Node.t() | (Node.t() -> Node.t())}
            | {:remove_node, Node.id()}
            | {:add_edge, Edge.t()}
            | {:remove_edge, Edge.t()}

    @type input_declar ::
            {:update_node_input, Node.id(), port_id :: atom(), new_input :: any()}
            | {:remove_node_input, Node.id(), port_id :: atom()}

    @type data_interventions ::
            {:override, Portkey.t(), data :: any()}
            | {:offset, Portkey.t(), data :: any()}
            | {:remove_interventions, Portkey.t()}

    @type t :: topology_mutation() | data_interventions() | input_declar()
  end

  alias Lily.Graph.Portkey
  alias Lily.Graph

  @type t :: %__MODULE__{
          # 越新的操作越靠前 (Head)
          undo_stack: [Operation.t()],
          # 越靠近当前时间点的“未来”越靠前
          redo_stack: [Operation.t()]
        }

  defstruct undo_stack: [], redo_stack: []

  @doc "初始化一个新的历史记录"
  def new, do: %__MODULE__{}

  @spec push(Lily.History.t(), any()) :: Lily.History.t()
  def push(%__MODULE__{undo_stack: undo} = history, op) do
    %{history | undo_stack: [op | undo], redo_stack: []}
  end

  @spec undo(Lily.History.t()) :: Lily.History.t()
  def undo(%__MODULE__{undo_stack: []} = history), do: history

  def undo(%__MODULE__{undo_stack: [last_op | rest_undo], redo_stack: redo} = history) do
    %{history | undo_stack: rest_undo, redo_stack: [last_op | redo]}
  end

  @spec redo(Lily.History.t()) :: Lily.History.t()
  def redo(%__MODULE__{redo_stack: []} = history), do: history

  def redo(%__MODULE__{undo_stack: undo, redo_stack: [next_op | rest_redo]} = history) do
    %{history | undo_stack: [next_op | undo], redo_stack: rest_redo}
  end

  @type effective_state :: %{
          graph: Graph.t(),
          overrides: %{Portkey.t() => any()},
          offsets: %{Portkey.t() => any()}
        }

  @doc """
  将所有的历史记录（过去）按时间顺序叠加到 base_graph 上。
  输出 Compiler 和 Orchid 真正需要的有效状态。
  """
  @spec resolve(Graph.t(), t()) :: effective_state()
  def resolve(%Graph{} = base_graph, %__MODULE__{undo_stack: undo_stack}) do
    # 为什么要 reverse？因为 undo_stack 的头部是最新的操作，
    # 我们要像看电影一样，从最古老的操作开始依次重播 (Replay)。
    chronological_ops = Enum.reverse(undo_stack)

    # 初始的折叠状态：图是原图，覆盖数据是空的
    initial_state = %{graph: base_graph, overrides: %{}, offsets: %{}}

    Enum.reduce(chronological_ops, initial_state, &apply_operation/2)
  end

  defp apply_operation({:add_node, node}, state) do
    %{state | graph: Graph.add_node(state.graph, node)}
  end

  defp apply_operation({:update_node, node_id, new_node}, state) do
    %{state | graph: Graph.update_node(state.graph, node_id, new_node)}
  end

  defp apply_operation({:remove_node, node_id}, state) do
    %{state | graph: Graph.remove_node(state.graph, node_id)}
  end

  defp apply_operation({:add_edge, edge}, state) do
    %{state | graph: Graph.add_edge(state.graph, edge)}
  end

  defp apply_operation({:remove_edge, edge}, state) do
    %{state | graph: Graph.remove_edge(state.graph, edge)}
  end

  defp apply_operation({:override, {:port, _, _} = port_key, value}, state) do
    %{state | overrides: Map.put(state.overrides, port_key, value)}
  end

  defp apply_operation({:offset, {:port, _, _} = port_key, value}, state) do
    %{state | offsets: Map.put(state[:offsets], port_key, value)}
  end

  defp apply_operation({:remove_interventions, {:port, _, _} = port_key}, state) do
    %{
      state
      | overrides: Map.delete(state[:overrides], port_key),
        offsets: Map.delete(state[:offsets], port_key)
    }
  end

  # defp apply_operation({:update_node_input, node_id, node_port, new_input}, state) do
  #   apply_operation(
  #     {:update_node, node_id,
  #      fn node = %Graph.Node{} -> %{node | maybe_input_context: new_input} end},
  #     state
  #   )
  # end
end
```

## Test

```elixir
defmodule LilyCompilerTest do
  use ExUnit.Case

  alias Lily.Graph
  alias Lily.Graph.{Node, Edge, Cluster}
  alias Lily.Compiler

  defp build_test_graph do
    nodes = [
      %Node{id: :split, impl: :dummy, inputs: [:val], outputs: [:out_a, :out_b]},
      %Node{id: :add,   impl: :dummy, inputs: [:a, :b], outputs: [:res]},
      %Node{id: :mul,   impl: :dummy, inputs: [:a, :b], outputs: [:res]},
      %Node{id: :inc,   impl: :dummy, inputs: [:val], outputs: [:res]},
      %Node{id: :dec,   impl: :dummy, inputs: [:val], outputs: [:res]}
    ]

    edges = [
      %Edge{from_node: :split, from_port: :out_a, to_node: :inc, to_port: :val},
      %Edge{from_node: :split, from_port: :out_b, to_node: :dec, to_port: :val},
      %Edge{from_node: :inc,   from_port: :res,   to_node: :add, to_port: :a},
      %Edge{from_node: :dec,   from_port: :res,   to_node: :add, to_port: :b},
      %Edge{from_node: :add,   from_port: :res,   to_node: :mul, to_port: :a}
    ]

    graph = Graph.new()
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    graph = Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))

    graph
  end

  test "图拓扑排序正确 (Topological Sort)" do
    graph = build_test_graph()
    {:ok, sorted_ids} = Graph.topological_sort(graph)

    assert hd(sorted_ids) == :split

    assert Enum.find_index(sorted_ids, &(&1 == :add)) > Enum.find_index(sorted_ids, &(&1 == :inc))
    assert Enum.find_index(sorted_ids, &(&1 == :add)) > Enum.find_index(sorted_ids, &(&1 == :dec))

    assert List.last(sorted_ids) == :mul
  end

  test "编译器：单集群编译与悬空参数识别" do
    graph = build_test_graph()

    effective_state = %{graph: graph, overrides: %{}, offsets: %{}}

    {:ok, recipes} = Compiler.compile(effective_state)

    assert length(recipes) == 1
    recipe = hd(recipes)

    assert :split_val in recipe.requires
    assert :mul_b in recipe.requires

    refute :inc_res in recipe.requires
  end

  test "编译器：硬核分簇切割与跨边缝合 (Cut & Bridge)" do
    graph = build_test_graph()
    effective_state = %{graph: graph, overrides: %{}, offsets: %{}}

    cluster_declara = %Cluster{
      node_colors: %{
        split: :cpu_cluster,
        inc:   :cpu_cluster,
        dec:   :cpu_cluster,
        add:   :gpu_cluster,
        mul:   :gpu_cluster
      }
    }

    {:ok, recipes} = Compiler.compile(effective_state, cluster_declara)

    assert length(recipes) == 2

    cpu_recipe = Enum.find(recipes, &(&1[:recipe].name == :cpu_cluster))
    gpu_recipe = Enum.find(recipes, &(&1[:recipe].name == :gpu_cluster))

    assert :split_val in cpu_recipe.requires

    assert :inc_res in cpu_recipe.exports
    assert :dec_res in cpu_recipe.exports

    assert :inc_res in gpu_recipe.requires
    assert :dec_res in gpu_recipe.requires

    assert :mul_b in gpu_recipe.requires
  end
end
```

Result:

```
➜ mix test
Running ExUnit with seed: 594731, max_cases: 24                                                                                                                    

.....
Finished in 0.08 seconds (0.00s async, 0.08s sync)
0 doctest, 3 tests, 0 failures
```
