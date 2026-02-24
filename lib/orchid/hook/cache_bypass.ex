defmodule Orchid.Hook.CacheBypass do
  @moduledoc """
  兼带短路的缓存。
  """
  @behaviour Orchid.Runner.Hook

  def call(ctx, next_fn) do
    next_fn.(ctx)
  end

  ## Prelude
  # 根据显式声明、应用配置、类型设置、默认设置获取缓存
  # 检查当前输入有无对应输出保存
  # * 有 => 获取结果直接返回
  # * 无 => 根据输入读取数据 if is_key else 不做任何事

  ## Postlude
  ## HashKey 生成
end
