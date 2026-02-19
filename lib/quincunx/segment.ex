defmodule Quincunx.Segment do
  @moduledoc """
  The smallest unit for incremental generation.
  """

  @type t :: %__MODULE__{
          id: any(),
          dependency: any(),
          record: Quincunx.Segment.RecorderAdapter.record(),
          cursor: Quincunx.Segment.RecorderAdapter.cursor(),
          snapshots: %{any() => Quincunx.Segment.DependencyAdapter.snapshot()},
          recorder_adapter: module(),
          dependency_adapter: module(),
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
    :dependency_adapter,
    extra: %{}
  ]
end
