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
alias Quincunx.Lily.{Graph, Graph.Node, Graph.Edge, Graph.Cluster, History, Compiler}

# 1. Build the static topology
graph = Graph.new()
|> Graph.add_node(%Node{id: :acoustic, impl: AcosticModel, inputs: [:lyrics], outputs: [:mel]})
|> Graph.add_node(%Node{id: :vocoder, impl: LegacyWaveNetVocoder,  inputs: [:mel], outputs: [:audio]})
|> Graph.add_edge(Edge.new(:acoustic, :mel, :vocoder, :mel))

# 2. Record user interventions (e.g., overriding AI tensors via UI)
history = History.new()
|> History.push({:override, {:port, :vocoder, :mel}, <<0, 1, "tensor_data">>})

# 3. Fold history into the current effective state
{graph, interventions} = History.resolve(graph, history)

# 4. Compile & Partition (Split execution to prevent VRAM overflow)
clusters = %Cluster{node_colors: %{acoustic: :gpu_1, vocoder: :gpu_2}}
{:ok, recipes} = Compiler.compile_graph(graph, clusters)
[bundle_1, bundle_2] = Compiler.bind_interventions(recipes, interventions)

# Result: 
# bundle_1 exports :"acoustic_mel"
# bundle_2 requires :"acoustic_mel" and carries the user override in its `overrides`.
```
---

## Source Code

```elixir
defmodule Quincunx.Lily.MixProject do
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

      iex> Quincunx.Lily.hello()
      :world

  """
  def hello do
    :world
  end
end

defmodule Quincunx.Lily.Compiler do
  @moduledoc """
  The final stage of the Lily pure functional pipeline.
  Translates the effective DAG into a sequence of Orchid.Recipe.
  """
  alias Quincunx.Lily.{Graph, History}
  alias Quincunx.Lily.Graph.{Node, Portkey, Cluster}

  @type port_key_name :: {:port, node_id :: Node.id(), port_name :: atom()}

  @type recipe_manifest :: %{
    recipe: Orchid.Recipe.t(),
    requires: [port_key_name()],
    exports: [port_key_name()],
    node_ids: [Lily.Graph.Node.id()]
  }

  @spec compile_graph(Lily.Graph.t()) :: {:error, :cycle_detected} | {:ok, [recipe_manifest()]}
  def compile_graph(%Graph{} = graph, cluster_declara \\ %Cluster{}) do
    case Graph.topological_sort(graph) do
      {:error, _} = err ->
        err

      {:ok, sorted_node_ids} ->
        node_colors = Cluster.paint_graph(sorted_node_ids, graph.edges, cluster_declara)

        clusters = Enum.group_by(sorted_node_ids, &Map.get(node_colors, &1, :default_cluster))

        static_recipes =
          Enum.map(clusters, fn {cluster_name, node_ids_in_cluster} ->
            build_recipe(cluster_name, node_ids_in_cluster, graph)
          end)

        {:ok, static_recipes}
    end
  end

  @spec bind_interventions([recipe_manifest()], History.inputs_bundle()) :: list()
  def bind_interventions(static_recipes, %{inputs: inputs, overrides: overrides, offsets: offsets}) do
    Enum.map(static_recipes, fn %{recipe: _recipe, node_ids: node_ids} = static_bundle ->
      # Extract node ids involved in this specific recipe cluster
      # node_ids_in_cluster = extract_recipe_nodes(recipe)

      # Filter data relevant to this cluster
      local_inputs = filter_port_data(inputs, node_ids)
      local_overrides = filter_port_data(overrides, node_ids)
      local_offsets = filter_port_data(offsets, node_ids)

      static_bundle
      |> Map.put(:overrides, local_overrides)
      |> Map.put(:offsets, local_offsets)
      |> Map.put(:inputs, local_inputs)
    end)
  end

  defp build_recipe(cluster_name, node_ids, graph) do
    steps =
      node_ids
      |> Enum.map(&Map.fetch!(graph.nodes, &1))
      |> Enum.map(&node_to_step(&1, graph))

    {requires, exports} = calculate_boundaries(node_ids, graph)

    # Strictly returns ONLY topology data
    %{
      recipe: Orchid.Recipe.new(steps, name: cluster_name),
      requires: requires,
      exports: exports,
      node_ids: node_ids
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

    step_outputs = Enum.map(node.outputs, fn p -> Portkey.to_orchid_key({:port, node.id, p}) end)

    build_orchid_step(node.impl, step_inputs, step_outputs, node.opts)
  end

  defp calculate_boundaries(node_ids_in_cluster, graph) do
    cluster_nodes_set = MapSet.new(node_ids_in_cluster)

    external_in_edges =
      graph.edges
      |> Enum.filter(&(&1.to_node in cluster_nodes_set and &1.from_node not in cluster_nodes_set))
      |> Enum.map(&Portkey.to_orchid_key({:port, &1.from_node, &1.from_port}))

    dangling_inputs =
      Enum.flat_map(node_ids_in_cluster, fn node_id ->
        node = graph.nodes[node_id]
        in_edges = Graph.get_in_edges(graph, node_id)

        node.inputs
        |> Enum.reject(fn port -> Enum.any?(in_edges, &(&1.to_port == port)) end)
        |> Enum.map(fn port -> Portkey.to_orchid_key({:port, node.id, port}) end)
      end)

    requires = Enum.uniq(external_in_edges ++ dangling_inputs)

    exports =
      graph.edges
      |> Enum.filter(&(&1.from_node in cluster_nodes_set and &1.to_node not in cluster_nodes_set))
      |> Enum.map(&Portkey.to_orchid_key({:port, &1.from_node, &1.from_port}))
      |> Enum.uniq()

    {requires, exports}
  end

  defp filter_port_data(data_map, node_ids) do
    data_map
    |> Enum.filter(fn {{:port, target_node, _port}, _data} -> target_node in node_ids end)
    |> Enum.into(%{})
  end

  # defp extract_recipe_nodes(%Orchid.Recipe{steps: steps}) do
  #   # Assuming step format is {Impl, Inputs, Outputs, Opts} and outputs start with "nodeid_port"
  #   # An alternative is storing node_ids in the recipe metadata.
  #   # We will simulate node extraction based on output keys:
  #   Enum.flat_map(steps, fn {_impl, _in, outs, _opts} ->
  #     Enum.map(outs, fn out_key ->
  #       out_key |> Atom.to_string() |> String.split("_") |> hd() |> String.to_atom()
  #     end)
  #   end) |> Enum.uniq()
  # end

  def build_orchid_step(impl, inputs, outputs, opts) do
    {impl, inputs, outputs, opts}
  end
end

defmodule Quincunx.Lily.Graph do
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

  # https://elixirforum.com/t/what-is-a-good-way-to-compare-structs/59303
  @spec same?(t(), t()) :: boolean()
  def same?(graph1, graph2), do: graph1 == graph2

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

defmodule Quincunx.Lily.Graph.Cluster do
  # 将依赖依照用户选择以及依赖关系分簇
  # 以实现并行控制
  # 人话：将部分很耗费资源的服务单独丢出去
  # 将整个并行改成串行 + 并行
  alias Quincunx.Lily.Graph.{Node, Edge}

  @type cluster_name :: atom() | String.t() | [cluster_name()]

  @type t :: %__MODULE__{
          node_colors: %{Node.id() => cluster_name()},
          merge_groups: [{cluster_name() | MapSet.t(cluster_name()), cluster_name()}]
        }
  defstruct node_colors: %{},
            merge_groups: []

  @spec paint_graph([Node.t()], MapSet.t(Edge.t()), Quincunx.Lily.Graph.Cluster.t()) ::
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

defmodule Quincunx.Lily.History do
  defmodule Operation do
    alias Quincunx.Lily.Graph.{Node, Edge, Portkey}

    @type topology_mutation ::
            {:add_node, Node.t()}
            | {:update_node, Node.id(),
               node_or_update_funtion :: Node.t() | (Node.t() -> Node.t())}
            | {:remove_node, Node.id()}
            | {:add_edge, Edge.t()}
            | {:remove_edge, Edge.t()}

    @type input_declar ::
            {:set_input, Portkey.t(), data :: any()}
            | {:remove_input, Portkey.t()}

    @type data_interventions ::
            {:override, Portkey.t(), data :: any()}
            | {:offset, Portkey.t(), data :: any()}
            | {:remove_interventions, Portkey.t()}

    @type t :: topology_mutation() | data_interventions() | input_declar()
  end

  alias Quincunx.Lily.Graph

  @type inputs_bundle :: %{
          :inputs => %{Lily.Graph.Portkey.t() => any()},
          :overrides => %{Lily.Graph.Portkey.t() => any()},
          :offsets => %{Lily.Graph.Portkey.t() => any()},
          optional(any()) => any()
        }

  @type effective_state :: {Lily.Graph.t(), inputs_bundle()}

  @type t :: %__MODULE__{
          # 越新的操作越靠前 (Head)
          undo_stack: [Operation.t()],
          # 越靠近当前时间点的“未来”越靠前
          redo_stack: [Operation.t()]
        }

  defstruct undo_stack: [], redo_stack: []

  @doc "初始化一个新的历史记录"
  def new, do: %__MODULE__{}

  @spec push(t(), any()) :: t()
  def push(%__MODULE__{undo_stack: undo} = history, op) do
    %{history | undo_stack: [op | undo], redo_stack: []}
  end

  @spec undo(t()) :: t()
  def undo(%__MODULE__{undo_stack: []} = history), do: history

  def undo(%__MODULE__{undo_stack: [last_op | rest_undo], redo_stack: redo} = history) do
    %{history | undo_stack: rest_undo, redo_stack: [last_op | redo]}
  end

  @spec redo(t()) :: t()
  def redo(%__MODULE__{redo_stack: []} = history), do: history

  def redo(%__MODULE__{undo_stack: undo, redo_stack: [next_op | rest_redo]} = history) do
    %{history | undo_stack: [next_op | undo], redo_stack: rest_redo}
  end

  @doc """
  将所有的历史记录（过去）按时间顺序叠加到 base_graph 上。
  输出 Compiler 和 Orchid 真正需要的有效状态。
  """
  @spec resolve(Graph.t(), t()) :: effective_state()
  def resolve(%Graph{} = base_graph, %__MODULE__{undo_stack: undo_stack}) do
    initial_state = %{graph: base_graph, inputs: %{}, overrides: %{}, offsets: %{}}

    undo_stack
    |> Enum.reverse()
    |> Enum.reduce(initial_state, &apply_operation/2)
    |> Map.pop(:graph)
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
    %{state | offsets: Map.put(state.offsets, port_key, value)}
  end

  defp apply_operation({:remove_interventions, {:port, _, _} = port_key}, state) do
    %{
      state
      | overrides: Map.delete(state.overrides, port_key),
        offsets: Map.delete(state.offsets, port_key)
    }
  end

  defp apply_operation({:set_input, port_key, data}, state) do
    %{state | inputs: Map.put(state.inputs, port_key, data)}
  end

  defp apply_operation({:remove_input, port_key}, state) do
    %{state | inputs: Map.delete(state.inputs, port_key)}
  end
end
```

## Test

```elixir
defmodule LilyCompilerTest do
  use ExUnit.Case

  alias Quincunx.Lily.Graph
  alias Quincunx.Lily.Graph.{Node, Edge, Cluster}
  alias Quincunx.Lily.Compiler

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

    {:ok, recipes} = Compiler.compile_graph(graph)

    assert length(recipes) == 1
    recipe = hd(recipes)

    assert :split_val in recipe.requires
    assert :mul_b in recipe.requires

    refute :inc_res in recipe.requires
  end

  test "编译器：硬核分簇切割与跨边缝合 (Cut & Bridge)" do
    graph = build_test_graph()

    cluster_declara = %Cluster{
      node_colors: %{
        split: :cpu_cluster,
        inc:   :cpu_cluster,
        dec:   :cpu_cluster,
        add:   :gpu_cluster,
        mul:   :gpu_cluster
      }
    }

    {:ok, recipes} = Compiler.compile_graph(graph, cluster_declara)

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

  test "编译器：两阶段编译 - 拓扑切割与数据缝合" do
    graph = build_test_graph()
    
    # 模拟 History 得到的 init_data (包含 inputs, overrides 等)
    init_data = %{
      inputs: %{ {:port, :split, :val} => 42 },
      overrides: %{ {:port, :inc, :res} => 100 },
      offsets: %{}
    }

    cluster_declara = %Cluster{
      node_colors: %{
        split: :cpu_cluster,
        inc:   :cpu_cluster,
        dec:   :cpu_cluster,
        add:   :gpu_cluster,
        mul:   :gpu_cluster
      }
    }

    # 第一阶段：纯拓扑编译
    {:ok, static_recipes} = Compiler.compile_graph(graph, cluster_declara)

    assert length(static_recipes) == 2
    
    cpu_recipe = Enum.find(static_recipes, &(&1[:recipe].name == :cpu_cluster))
    assert :split_val in cpu_recipe.requires
    refute Map.has_key?(cpu_recipe, :overrides) # 确保没有包含侧载数据

    # 第二阶段：数据绑定 (Downstream Enumerable Mapping)
    final_bundles = Compiler.bind_interventions(static_recipes, init_data)
    
    # 验证数据是否被正确分发到对应的 bundle
    cpu_bundle = Enum.find(final_bundles, &(&1[:recipe].name == :cpu_cluster))
    gpu_bundle = Enum.find(final_bundles, &(&1[:recipe].name == :gpu_cluster))

    # CPU 集群包含了 :split 的 input 和 :inc 的 override
    assert cpu_bundle.inputs[{:port, :split, :val}] == 42
    assert cpu_bundle.overrides[{:port, :inc, :res}] == 100
    
    # GPU 集群没有任何干预数据
    assert map_size(gpu_bundle.overrides) == 0
  end
end
```

Result:

```plain
➜ mix test --cover
Cover compiling modules ...                                                                                                                                        
Running ExUnit with seed: 288564, max_cases: 24

......
Finished in 0.1 seconds (0.00s async, 0.1s sync)
1 doctest, 5 tests, 0 failures

Generating cover results ...

| Percentage | Module                 |
|------------|------------------------|
|      0.00% | Quincunx.Lily.Graph.Edge        |
|      0.00% | Quincunx.Lily.History           |
|     62.86% | Quincunx.Lily.Graph             |
|     97.92% | Quincunx.Lily.Compiler          |
|    100.00% | Lily                   |
|    100.00% | Quincunx.Lily.Graph.Cluster     |
|    100.00% | Quincunx.Lily.Graph.Node        |
|    100.00% | Quincunx.Lily.Graph.Portkey     |
|    100.00% | Quincunx.Lily.History.Operation |
|------------|------------------------|
|     70.94% | Total                  |

Coverage test failed, threshold not met:

    Coverage:   70.94%
    Threshold:  90.00%

Generated HTML coverage results in "cover" directory
```
