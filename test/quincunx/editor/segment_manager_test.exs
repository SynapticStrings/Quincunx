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
      {:ok, mgr} = remove_segment(mgr, "Foo")

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
      mgr = new() |> create_tag("Foo")

      assert mgr.tag_indexer.tag_index["Foo"] == MapSet.new([])
    end

    test "apply_tag/3" do
      seg_fac = &Segment.new(&1, Graph.new())

      {:ok, mgr} = new() |> add_segment(seg_fac.("I"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("II"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("III"))

      mgr = apply_tag(mgr, "Tag1", ["I", "II", "III", "IV"])
      mgr = apply_tag(mgr, "Tag2", ["I", "II"])

      assert Map.keys(mgr.tag_indexer.tag_index) |> Enum.sort() == ["Tag1", "Tag2"]
      assert MapSet.to_list(mgr.tag_indexer.segment_index["III"]) == ["Tag1"]
    end

    test "divest_tag/2" do
      seg_fac = &Segment.new(&1, Graph.new())

      {:ok, mgr} = new() |> add_segment(seg_fac.("I"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("II"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("III"))

      mgr =
        mgr
        |> apply_tag("Tag1", ["I", "II", "III", "IV"])
        |> apply_tag("Tag2", ["I", "II"])
        |> divest_tag("Tag1", "I")
        |> divest_tag("Tag2", "III")

      refute MapSet.member?(mgr.tag_indexer.tag_index["Tag1"], "I")
      refute MapSet.member?(mgr.tag_indexer.tag_index["Tag2"], "III")
      assert MapSet.member?(mgr.tag_indexer.tag_index["Tag1"], "II")
      assert MapSet.member?(mgr.tag_indexer.tag_index["Tag2"], "II")
    end

    test "delete_tag/2 without segments attached" do
      mgr = new() |> create_tag("Foo") |> delete_tag("Foo") |> delete_tag("Baz")

      assert map_size(mgr.tag_indexer.tag_index) == 0
    end

    test "delete_tag/2 with segment attached" do
      seg_fac = &Segment.new(&1, Graph.new())

      {:ok, mgr} = new() |> add_segment(seg_fac.("I"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("II"))
      {:ok, mgr} = add_segment(mgr, seg_fac.("III"))

      mgr = apply_tag(mgr, "Tag1", ["I", "II", "III", "IV"])
      mgr = apply_tag(mgr, "Tag2", ["I", "II"])

      delete_tag(mgr, "Tag1") |> IO.inspect()
    end
  end
end
