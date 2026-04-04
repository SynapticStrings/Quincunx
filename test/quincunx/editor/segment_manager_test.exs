defmodule Quincunx.Editor.SegmentManagerTest do
  use ExUnit.Case

  alias Quincunx.Editor.Segment
  alias Quincunx.Topology.Graph
  import Quincunx.Editor.SegmentManager

  describe "Simple Segment CRUD" do
    test "add_segment/2" do
      {:ok, mgr} = new() |> add_segment(Segment.new("Foo", Graph.new()))

      # Segment Store.
      {:ok, foo} = get_segment(mgr, "Foo")
      assert foo.id == "Foo"

      # Tag Indexer.
      assert get_in(mgr, [Access.key!(:tag_indexer), Access.key!(:segment_index)]) |> Map.keys() ==
               ["Foo"]

      # Dependency Graph.
      assert get_in(mgr, [Access.key!(:dep_graph), Access.key!(:nodes)]) |> MapSet.to_list() ==
               ["Foo"]
    end

    test "remove_segment/2" do
      {:ok, mgr} = new() |> add_segment(Segment.new("Foo", Graph.new()))
      mgr = mgr |> remove_segment("Foo")

      # Segment Store.
      assert get_in(mgr, [Access.key!(:segments)]) |> map_size() == 0

      # Tag Indexer.
      assert get_in(mgr, [Access.key!(:tag_indexer), Access.key!(:segment_index)]) |> Map.keys() ==
               []

      # Dependency Graph.
      assert get_in(mgr, [Access.key!(:dep_graph), Access.key!(:nodes)]) |> MapSet.to_list() ==
               []
    end
  end

  describe "Tag Operation" do
    test "create_tag/2" do
      # ...
    end
  end
end
