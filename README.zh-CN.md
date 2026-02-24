# ⁙Quincunx⁙

针对异质性批量数据的增量生成引擎（原 QyCore）。

*尽管设计的愿景为实现交互式歌声合成编辑器，但 Quincunx 保持领域无关，不会引入领域相关的依赖以及代码。*

## 关键点

### 增量生成的粒度控制

### 用户修改覆盖上游模型生成的情况

### 增量生成的缓存机制

### 异构设备的并行策略考虑

## 进程模型与核心对象

### `Quincunx.Session`

### `Quincunx.Segment`

---

# 目前的进度/问题

## 完善 `Nodes/Edges => Orchid Recipes` 的过程

```elixir
# API
@spec compile(Quincunx.Dependency.t()) :: %{
  cluster_name() | [cluster_name()] =>
  {
    [Orchid.Step.t()],
    %{inputs: any(), overrides: any(), offsets: any()}
  }
}
```
