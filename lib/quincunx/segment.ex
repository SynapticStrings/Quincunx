defmodule Quincunx.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  """
  alias Quincunx.Segment, as: Seg
  alias Quincunx.Dependency

  @type t :: %__MODULE__{
          id: any(),
          dependency: Dependency.t(),
          record: Seg.RecorderAdapter.record(),
          cursor: Seg.RecorderAdapter.cursor(),
          snapshots: %{any() => Seg.DependencyAdapter.snapshot()},
          recorder_adapter: module(),
          extra: map()
        }
  defstruct [
    :id,
    # 记录依赖图
    # 其中最重要的是 required_inputs_fields
    # 以及 optional_input_fields
    :dependency,
    # 记录此前的一系列操作
    :record,
    # 记录最新操作的指针（？）
    :cursor,
    # 上一次渲染动作后的数据
    # 大容量数据则为 Ref
    :snapshots,
    # 一系列的适配器
    :recorder_adapter,
    extra: %{}
  ]
end
