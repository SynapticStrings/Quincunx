defmodule LilyCompilerTest do
  use ExUnit.Case

  alias Quincunx.Lily.RecipeBundle
  alias Quincunx.Lily.Graph
  alias Quincunx.Lily.Graph.{Node, Edge, Cluster}
  alias Quincunx.Lily.Compiler

  defp build_test_graph do
    nodes = [
      %Node{id: :split, impl: :dummy, inputs: [:val], outputs: [:out_a, :out_b]},
      %Node{id: :add, impl: :dummy, inputs: [:a, :b], outputs: [:res]},
      %Node{id: :mul, impl: :dummy, inputs: [:a, :b], outputs: [:res]},
      %Node{id: :inc, impl: :dummy, inputs: [:val], outputs: [:res]},
      %Node{id: :dec, impl: :dummy, inputs: [:val], outputs: [:res]}
    ]

    edges = [
      %Edge{from_node: :split, from_port: :out_a, to_node: :inc, to_port: :val},
      %Edge{from_node: :split, from_port: :out_b, to_node: :dec, to_port: :val},
      %Edge{from_node: :inc, from_port: :res, to_node: :add, to_port: :a},
      %Edge{from_node: :dec, from_port: :res, to_node: :add, to_port: :b},
      %Edge{from_node: :add, from_port: :res, to_node: :mul, to_port: :a}
    ]

    graph = Graph.new()
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    graph = Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))

    graph
  end

  describe "graph test" do
    test "ensure correct topological sort" do
      graph = build_test_graph()
      {:ok, sorted_ids} = Graph.topological_sort(graph)

      assert hd(sorted_ids) == :split

      assert Enum.find_index(sorted_ids, &(&1 == :add)) >
               Enum.find_index(sorted_ids, &(&1 == :inc))

      assert Enum.find_index(sorted_ids, &(&1 == :add)) >
               Enum.find_index(sorted_ids, &(&1 == :dec))

      assert List.last(sorted_ids) == :mul
    end
  end

  describe "compiler test" do
    test "compiling with single cluster and recognise hanging params" do
      graph = build_test_graph()

      {:ok, recipes} = Compiler.compile_graph(graph)

      assert length(recipes) == 1
      recipe = hd(recipes)

      assert :split_val in recipe.requires
      assert :mul_b in recipe.requires

      refute :inc_res in recipe.requires
    end

    test "clusters split and merge via bridge" do
      graph = build_test_graph()

      cluster_declara = %Cluster{
        node_colors: %{
          split: :cpu_cluster,
          inc: :cpu_cluster,
          dec: :cpu_cluster,
          add: :gpu_cluster,
          mul: :gpu_cluster
        }
      }

      {:ok, recipes} = Compiler.compile_graph(graph, cluster_declara)

      assert length(recipes) == 2

      cpu_recipe = Enum.find(recipes, &(&1.recipe.name == :cpu_cluster))
      gpu_recipe = Enum.find(recipes, &(&1.recipe.name == :gpu_cluster))

      assert :split_val in cpu_recipe.requires

      assert :inc_res in cpu_recipe.exports
      assert :dec_res in cpu_recipe.exports

      assert :inc_res in gpu_recipe.requires
      assert :dec_res in gpu_recipe.requires

      assert :mul_b in gpu_recipe.requires
    end

    test "两阶段编译 - 拓扑切割与数据缝合" do
      graph = build_test_graph()

      init_data = %{
        "inputs" => %{{:port, :split, :val} => 42},
        "overrides" => %{{:port, :inc, :res} => 100}
      }

      cluster_declara = %Cluster{
        node_colors: %{
          split: :cpu_cluster,
          inc: :cpu_cluster,
          dec: :cpu_cluster,
          add: :gpu_cluster,
          mul: :gpu_cluster
        }
      }

      {:ok, static_recipes} = Compiler.compile_graph(graph, cluster_declara)

      assert length(static_recipes) == 2

      cpu_recipe = Enum.find(static_recipes, &(&1.recipe.name == :cpu_cluster))
      assert :split_val in cpu_recipe.requires

      assert map_size(RecipeBundle.get_interventions(cpu_recipe, :overrides)) == 0

      final_bundles = Compiler.bind_interventions(static_recipes, init_data)

      cpu_bundle = Enum.find(final_bundles, &(&1.recipe.name == :cpu_cluster))
      gpu_bundle = Enum.find(final_bundles, &(&1.recipe.name == :gpu_cluster))

      assert RecipeBundle.get_intervention(cpu_bundle, "inputs", {:port, :split, :val}) == 42

      assert RecipeBundle.get_intervention(cpu_bundle, "overrides", {:port, :inc, :res}) == 100

      assert map_size(RecipeBundle.get_interventions(gpu_bundle, :overrides)) == 0
    end
  end
end
