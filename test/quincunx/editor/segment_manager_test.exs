defmodule Quincunx.Editor.SegmentManagerTest do
  use ExUnit.Case

  alias Quincunx.Editor.Segment
  alias Quincunx.Topology.{Graph, LiteGraph}
  import Quincunx.Editor.SegmentManager

  # 辅助函数
  defp seg(id), do: Segment.new(id, Graph.new())

  def unwrap_ok({:ok, val}), do: val
  def unwrap_ok({:error, reason}), do: flunk("Expected :ok, got: #{inspect(reason)}")
  def unwrap_ok(val), do: val

  describe "Simple Segment CRUD" do
    test "add_segment/2 registers segment, updates tag indexer & dep graph" do
      {:ok, mgr} = new() |> add_segment(seg("Foo"))

      # Segment Store
      assert {:ok, foo} = get_segment(mgr, "Foo")
      assert foo.id == "Foo"

      # Tag Indexer (auto-initialized)
      assert Map.keys(mgr.tag_indexer.segment_index) == ["Foo"]

      # Dependency Graph
      assert MapSet.to_list(mgr.dep_graph.nodes) |> Enum.sort() == ["Foo"]
      assert mgr.dirty == MapSet.new(["Foo"])
    end

    test "add_segment/2 returns error on duplicate" do
      {:ok, mgr1} = new() |> add_segment(seg("Foo"))
      assert {:error, :already_exists} = add_segment(mgr1, seg("Foo"))
    end

    test "remove_segment/2 cleans up all related structures" do
      {:ok, mgr} =
        new()
        |> add_segment(seg("Foo"))
        |> unwrap_ok()
        |> apply_tag("tg", "Foo")
        |> remove_segment("Foo")

      assert map_size(mgr.segments) == 0
      assert mgr.tag_indexer.segment_index == %{}
      assert mgr.tag_indexer.tag_index["tg"] == MapSet.new()
      assert mgr.dep_graph.nodes == MapSet.new()
      assert mgr.dirty == MapSet.new()
    end

    test "remove_segment/2 returns error on missing segment" do
      mgr = new()
      assert {:error, :not_exists} = remove_segment(mgr, "Missing")
    end

    test "get_segment/2 and segment_ids/1" do
      {:ok, mgr} = new() |> add_segment(seg("A")) |> unwrap_ok() |> add_segment(seg("B"))
      assert {:ok, _} = get_segment(mgr, "A")
      assert {:error, :not_exists} = get_segment(mgr, "C")
      assert segment_ids(mgr) |> Enum.sort() == ["A", "B"]
    end

    test "other scenario related to update(only in Quincunx.Editor.SegmentStore.update_segment/3)" do
      mgr =
        new() |> add_segment(seg("Foo")) |> unwrap_ok() |> add_segment(seg("Bar")) |> unwrap_ok()

      assert {:error, :segment_id_changed} ==
               Quincunx.Editor.SegmentStore.update_segment(mgr.segments, "Foo", fn seg ->
                 %{seg | id: "Baz"}
               end)

      assert {:error, :segment_id_conflict} ==
               Quincunx.Editor.SegmentStore.update_segment(mgr.segments, "Foo", fn seg ->
                 %{seg | id: "Bar"}
               end)
    end
  end

  describe "Tag Operation" do
    test "create_tag/2 preserves existing tags (Regression for Bug #1)" do
      mgr = new() |> create_tag("T1") |> create_tag("T2")
      assert Map.keys(mgr.tag_indexer.tag_index) |> Enum.sort() == ["T1", "T2"]
    end

    test "apply_tag/3 filters non-existent segments & auto-creates tag" do
      {:ok, mgr} = new() |> add_segment(seg("I")) |> unwrap_ok() |> add_segment(seg("II"))

      # "IV" 不存在应被忽略
      mgr = apply_tag(mgr, "Tag1", ["I", "II", "IV"])

      assert Map.keys(mgr.tag_indexer.tag_index) == ["Tag1"]
      assert MapSet.to_list(mgr.tag_indexer.tag_index["Tag1"]) |> Enum.sort() == ["I", "II"]
      assert MapSet.to_list(mgr.tag_indexer.segment_index["I"]) == ["Tag1"]
    end

    test "divest_tag/2 removes tag from both indices" do
      mgr =
        new()
        |> add_segment(seg("I"))
        |> unwrap_ok()
        |> add_segment(seg("II"))
        |> unwrap_ok()
        |> apply_tag("T1", ["I", "II"])
        |> divest_tag("T1", "I")

      refute MapSet.member?(mgr.tag_indexer.tag_index["T1"], "I")
      assert MapSet.member?(mgr.tag_indexer.tag_index["T1"], "II")
      refute MapSet.member?(mgr.tag_indexer.segment_index["I"], "T1")
    end

    test "delete_tag/2 cleans forward & backward indices" do
      mgr =
        new()
        |> add_segment(seg("I"))
        |> unwrap_ok()
        |> apply_tag("T1", ["I"])
        |> delete_tag("T1")

      assert Map.has_key?(mgr.tag_indexer.tag_index, "T1") == false
      assert mgr.tag_indexer.segment_index["I"] == MapSet.new()
      # 删除不存在的标签应幂等
      mgr = delete_tag(mgr, "Ghost")
      assert mgr.tag_indexer.tag_index == %{}
    end
  end

  describe "Dependency Management" do
    test "add_dependency/3 & remove_dependency/4" do
      mgr =
        new()
        |> add_segment(seg("A"))
        |> unwrap_ok()
        |> add_segment(seg("B"))
        |> unwrap_ok()
        |> add_dependency("A", "B")

      assert MapSet.member?(mgr.dep_graph.nodes, "A")
      # 假设 LiteGraph 有 edges 或可通过依赖关系推断
      # 此处依赖你的 LiteGraph 具体实现，通常可通过检查 dependents 验证
      assert MapSet.member?(LiteGraph.dependents(mgr.dep_graph, "A"), "B")

      mgr = remove_dependency(mgr, "A", "B")
      assert MapSet.size(LiteGraph.dependents(mgr.dep_graph, "A")) == 0
    end
  end

  describe "Dirty Propagation & Dispatch" do
    test "propagate_dirty marks dependents transitively" do
      mgr =
        new()
        |> add_segment(seg("A"))
        |> unwrap_ok()
        |> add_segment(seg("B"))
        |> unwrap_ok()
        |> add_segment(seg("C"))
        |> unwrap_ok()
        |> add_dependency("A", "B")
        |> add_dependency("B", "C")
        |> clear_dirty(["C", "B"])

      # 初始只有 A 脏
      assert mgr.dirty == MapSet.new(["A"])

      # 围殴顺应下面的测试代码现在也把 A 变干净
      mgr = mgr |> clear_dirty(["A"])

      # 操作 B 应使 B 及其依赖 C 变脏（假设 propagate_dirty 逻辑正确）
      mgr = apply_operation(mgr, "B", {:add_node, %{id: "x"}})
      assert MapSet.member?(mgr.dirty, "B")
      assert MapSet.member?(mgr.dirty, "C")
      # A 不是 B 的依赖，不应变脏
      refute MapSet.member?(mgr.dirty, "A")
    end

    test "grouped_dispatch_order returns topological stages" do
      mgr =
        new()
        |> add_segment(seg("A"))
        |> unwrap_ok()
        |> add_segment(seg("B"))
        |> unwrap_ok()
        |> add_segment(seg("C"))
        |> unwrap_ok()
        |> add_segment(seg("D"))
        |> unwrap_ok()
        |> add_dependency("A", "B")
        |> add_dependency("A", "C")
        |> add_dependency("B", "D")
        |> add_dependency("C", "D")

      # 1. 只有 A 脏 -> 下游 B, C, D 都应重算
      mgr_a_dirty = %{mgr | dirty: MapSet.new(["A"])}
      assert {:ok, stages_a} = grouped_dispatch_order(mgr_a_dirty)
      # 拓扑分层应为：[["A"], ["B", "C"], ["D"]]
      assert length(stages_a) == 3
      assert Enum.sort(List.flatten(stages_a)) == ["A", "B", "C", "D"]

      # 2. 只有 D 脏 -> 上游 A, B, C 无需重算，仅 D 需调度
      mgr_d_dirty = %{mgr | dirty: MapSet.new(["D"])}
      assert {:ok, stages_d} = grouped_dispatch_order(mgr_d_dirty)
      # 预期仅输出 D（因为 A, B, C 干净，且不是 D 的下游）
      assert length(stages_d) == 1
      assert List.flatten(stages_d) == ["D"]
    end

    test "grouped_dispatch_order returns empty when no dirty segments" do
      mgr = %{new() | dirty: MapSet.new()}
      assert {:ok, []} = grouped_dispatch_order(mgr)
    end

    test "clear_dirty removes rendered IDs from dirty set" do
      mgr = %{new() | dirty: MapSet.new(["A", "B", "C"])}
      mgr = clear_dirty(mgr, ["B"])
      assert mgr.dirty == MapSet.new(["A", "C"])
    end
  end

  describe "Segment Operations & History" do
    # 需要将相关业务（脏传播）移至后续流程吗？
    test "apply_operation/3 pushes to history" do
      {:ok, mgr} = new() |> add_segment(seg("S1"))
      mgr = %{mgr | dirty: MapSet.new()}

      op = {:add_node, %{id: "new_node"}}
      mgr = apply_operation(mgr, "S1", op)

      assert MapSet.member?(mgr.dirty, "S1")
      {:ok, seg} = get_segment(mgr, "S1")
      assert seg.history.undo_stack == [op]
      assert seg.history.redo_stack == []
    end

    test "undo/2 & redo/2 work correctly" do
      {:ok, mgr} = new() |> add_segment(seg("S1"))
      mgr = apply_operation(mgr, "S1", {:add_node, %{id: "N1"}})
      mgr = apply_operation(mgr, "S1", {:add_edge, %{id: "E1"}})

      mgr = undo(mgr, "S1")
      {:ok, s} = get_segment(mgr, "S1")
      assert length(s.history.undo_stack) == 1
      assert length(s.history.redo_stack) == 1

      mgr = redo(mgr, "S1")
      {:ok, s} = get_segment(mgr, "S1")
      assert length(s.history.undo_stack) == 2
      assert length(s.history.redo_stack) == 0
    end

    test "operations on non-existent segment return manager unchanged" do
      mgr = new()
      mgr2 = apply_operation(mgr, "Ghost", {:add_node, %{}})
      assert mgr2 == mgr
    end
  end
end
