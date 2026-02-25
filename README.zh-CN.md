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

### `Quincunx.Segment`/`Lily`

- 修改 `Lily.Graph` 使输入与拓扑结构解耦
    - 使 `Lily.History` 的操作对象包含了图以及输入本体
- 修改 `Lily.Compiler.build_recipe/4` 使输出仅与 `recipe, requires, exports` 有关
- 修改 `Lily.Compiler.compile/2` 的入参改成图本体与 some middle state ，添加下游函数：
    - `Enum.map(init_data, graph_middle) => recipe bundle`
- `Quincunx.Session.Segment, Quincunx.Session.Graph`
