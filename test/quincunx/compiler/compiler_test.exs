defmodule Quincunx.Compiler.CompilerTest do
  use ExUnit.Case

  import Quincunx.Compiler.GraphBuilder
  alias Quincunx.Compiler.RecipeBundle
  alias Quincunx.Topology.Cluster
  import QuincunxTest.GraphFactory

  describe "GraphBuilder" do
    test "compile_graph/2 without cluster" do
      {:ok, [%RecipeBundle{} = recipe_bundle]} =
        compile_graph(build_finin_and_fanout_dag())

      assert "step1|in" in recipe_bundle.requires
      assert "step4|out1" in recipe_bundle.exports
    end

    test "compile_graph/2 with cluster" do
      {:ok, [bundle_last, bundle_first]} =
        compile_graph(build_finin_and_fanout_dag(), %Cluster{node_colors: %{step3: :red}})

      assert "step1|out" in bundle_first.exports
      assert "step1|out" in bundle_last.requires
    end
  end

  describe "RecipeBundle" do
    import Quincunx.Compiler.RecipeBundle

    setup do
      {:ok, graph} =
        compile_graph(build_finin_and_fanout_dag(), %Cluster{node_colors: %{step3: :red}})

      [graph: graph]
    end

    test "bind_interventions without extra interventions", %{graph: graph} do
      mock_interventions = %{
        {:port, :step1, :in} => {:input, "Foo"},
        {:port, :step2, :in} => {:input, "Bar"}
      }

      [_, first_bundle] = bind_interventions(graph, mock_interventions)

      assert Map.get(first_bundle.interventions, {:port, :step1, :in}) == {:input, "Foo"}
    end

    test "bind_interventions with extra interventions", %{graph: graph} do
      mock_interventions = %{
        {:port, :step1, :in} => {:input, "Foo"},
        {:port, :step2, :in} => {:input, "Bar"}
      }

      exist_intervention = %{
        {:port, :step4, :out1} => {:override, "Fin"}
      }

      [last_bundle, _] = bind_interventions(graph, mock_interventions, exist_intervention)

      assert Map.get(last_bundle.interventions, {:port, :step4, :out1}) == {:override, "Fin"}
      assert Map.get(last_bundle.interventions, {:port, :step4, :out2}) == nil
    end
  end

  describe "Facade" do
    import Quincunx.Compiler

    test "compile_to_recipes/1" do
      {:ok, [{"Foo", [bundle2, bundle1]}]} =
        Quincunx.Editor.Segment.new("Foo", build_finin_and_fanout_dag(), %Cluster{
          node_colors: %{step3: :red}
        })
        |> compile_to_recipes()

      assert is_struct(bundle1, RecipeBundle)
      assert is_struct(bundle2, RecipeBundle)
    end
  end
end
