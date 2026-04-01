defmodule Quincunx.Editor.HistoryResolverTest do
  use ExUnit.Case

  import Quincunx.Editor.History.Resolver
  alias Quincunx.Editor.History
  import QuincunxTest.GraphFactory

  describe "Normal resolve behaviour" do
    test "resolve required a graph and history records" do
      assert {%Quincunx.Topology.Graph{}, %{}} =
               resolve(History.new(), build_finin_and_fanout_dag())
    end
  end

  describe "Edge" do
    # ...
  end
end
