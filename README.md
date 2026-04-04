# [WIP] Quincunx

> [!IMPORTANT]
>
> To ensure development efficiency, documentation and comments will be in Chinese currently.
> Once the API was consolidate, I'll translate docs and comments into English.

用于存在外部数据介入的增量生成任务的轻量级编排核心。

_尽管最初的愿景是实现一个交互式歌唱合成编辑器，但 Quincunx 仍然保持领域无关性，并且不会引入特定领域的依赖项。_

## 特征

- 整合 OTP/GenServer 服务（基于 [OrchidSymbiont](https://github.com/SynapticStrings/OrchidSymbiont)）
- 基于 [OrchidStratum](https://github.com/SynapticStrings/OrchidStratum) 的自动确定性缓存（可以实现基于 `Segment` 的增量生成）
- 异构设备调度的潜能

## 范畴

Quincunx 是：

- 一个用于应用的调度核心
- 使用服务无关（Python / NIF / ONNX / HTTP 服务）
- 专为需要人类的精细调制/介入的任务而设计
- 嵌入在 BEAM 系统之中

Quincunx 不是：

- 歌声合成编辑器
- DAW
- UI 框架
- 训练集合
- 声学模型实现

## 开发进度

- [x] 可运行任务
- [ ] 整合缓存并运行
- [ ] 工程可以被导出/加载为文件
- [ ] 一点面向编辑器的小改动

## Roadmap

> 这一节用于描述 Quincunx 当前重构阶段的整体方向，而非承诺固定 API。  
> 在内核语义稳定之前，部分模块、命名与接口仍可能调整。

### 核心定位

Quincunx 的目标不是成为一个特定领域的编辑器，而是提供一套可嵌入在 BEAM 生态中的**增量生成编排内核**。

其核心关注点可以概括为：

- **DAG**：描述纯结构化的执行依赖
- **Intervention**：描述外部数据与人工修改如何介入 DAG
- **Incremental Generation**：通过局部重编译、局部失效与运行时缓存，实现交互式生成

换言之：

- `Quincunx = DAG + Intervention + Incremental Generation`
- `Quincunx + DomainApp + UI = Editor`

Quincunx 本身不拥有具体领域语义；领域对象、文件格式、UI 行为、标签规范等应由上层 DomainApp 定义。

---

### 当前重构目标

当前版本的重点不是扩展功能面，而是**收敛内核结构与语义边界**，主要包括：

- 明确编辑态、编译态、运行态三者的分层
- 明确 `Session` / `Context` / `SegmentManager` 的职责边界
- 明确 `Intervention` 的内部表示与 Orchid 运行时表示之间的适配边界
- 明确“编译缓存”、“运行时黑板缓存”、“底层 OrchidStratum 缓存”的层次关系
- 为后续导出/导入、增量生成、跨 Session 扩展打下稳定基础

---

### 近期路线

#### 1. 收敛核心数据模型

- [ ] 统一 `Intervention` 的内部 canonical format
- [ ] 明确 `PortRef` 与 Orchid port key 之间的转换边界
- [ ] 统一 `History -> Resolver -> Compiler -> Worker` 链路中的数据形状
- [ ] 清理已漂移的 `@type` / `@spec` / 实现不一致问题

说明：

- Quincunx 内部更适合使用 `{:port, node_id, port_name}` 表达图中的端口引用
- Orchid 运行时更适合使用 `orchid_key`
- 二者之间应由明确的 adapter/边界层转换，而不是在业务逻辑中混用

---

#### 2. 收敛 Session 与 Segment 管理结构

- [ ] 以 `Session.Context` 作为运行时状态容器
- [ ] 将 `SegmentManager` 收敛为 `Context` 内部的 segment domain state owner
- [ ] 避免 `Context` 与 `SegmentManager` 并行维护两套 segment 集合状态
- [ ] 明确 inter-segment dependency、dirty propagation、tag filtering 如何进入主调度链

目标：

- `Context` 负责 session runtime state
- `SegmentManager` 负责 segment 集合、tag、依赖、dirty
- 避免后续出现编辑态与运行态的“分裂状态模型”

---

#### 3. 收敛缓存语义

- [ ] 区分并固定三层缓存的职责
- [ ] 将静态编译缓存与动态 intervention 绑定拆开
- [ ] 明确 topology 变化与 data intervention 变化的失效规则
- [ ] 在不引入额外复杂度的前提下先完成正确性，再考虑 ETS / 外部缓存优化

当前规划中的三层缓存：

1. **Compile Cache**
   - 缓存 graph/cluster 编译后的静态结构（如 static bundles）
   - 应只受 topology / cluster 变化影响

2. **Blackboard**
   - 缓存当前 session render pass 的中间结果与输出
   - 为后续 bundle / segment 提供依赖输入

3. **OrchidStratum / Bypass Cache**
   - 缓存底层执行结果
   - 属于更低层、面向运行时复用的 deterministic cache

这三层缓存并不等价，也不应互相替代。

---

#### 4. 打通真正的增量执行链

- [ ] 让 dirty segment 与其 dependents 的调度逻辑完整进入 render 主链路
- [ ] 明确 segment 级 stage 与 bundle 级 stage 的组合方式
- [ ] 完善 render 成功 / 失败 / 中断时的 dirty 语义
- [ ] 逐步整合 OrchidStratum 与 OrchidIntervention

目标是实现：

- 局部修改只失效必要 segment
- 局部 intervention 不触发不必要的静态重编译
- session 内部具备可预期、可恢复、可观察的调度行为

---

### 中期路线

#### 5. 面向 DomainApp 的可扩展性整理

- [ ] 继续保留 tag 机制的开放性
- [ ] 明确 tag 仅作为 metadata / index / filtering 机制
- [ ] 避免在内核中硬编码具体领域标签语义
- [ ] 为 DomainApp 提供更稳定的 Session API 与 dispatch API

Tag 的设计目标是：

- 允许 DomainApp 按自身格式组织 segment
- 支持批量操作、分组、筛选、选择范围控制
- 不让 Quincunx 本身依赖特定领域模型

推荐但不强制的约定形式示例：

- `group:verse`
- `track:vocal`
- `speaker:miku`
- `state:selected`

---

#### 6. 导出 / 导入与快照能力

- [ ] 定义可持久化的数据边界
- [ ] 区分“项目状态”和“运行态状态”
- [ ] 为 future editor / host app 提供可序列化的工程结构
- [ ] 补充 snapshot / restore 语义

大致原则：

- `Segment` / `History` / `Tag` / dependency 等可视为项目态数据
- `Task`、PID、运行中的 render ref 等应视为纯运行态数据
- cache 是否序列化应按层次分别讨论，而非统一处理

---

### 长期路线

#### 7. 更明确的执行边界与异构调度能力

- [ ] 更清晰地表达 step / service / worker 的边界
- [ ] 支持不同运行后端（Python / NIF / HTTP / ONNX runtime 等）
- [ ] 为不同资源域、设备域、cluster 策略预留接口
- [ ] 逐步完善调度策略，而非仅限于 barrier 模式

#### 8. 更完整的可观测性与调试支持

- [ ] 渲染/编译路径的结构化日志
- [ ] dispatch / worker / cache hit/miss 的调试信息
- [ ] 更明确的错误分类
- [ ] 与测试、覆盖率、静态分析一起构成更稳定的重构反馈回路

---

### 当前需要继续设计的问题

以下问题仍在收敛中，暂不承诺最终接口：

- `Intervention` 的最终结构是否保持与 OrchidIntervention 完全一致，或在 Quincunx 内部采用独立 canonical format
- `SegmentManager` 是否完全作为 `Context` 的内部状态子系统
- `Planner` 是否同时统一 segment 级与 bundle 级调度
- cache key / fingerprint 的最终策略
- snapshot / export 的边界定义
- plugin API 是否继续保持当前形式，或收敛到更明确的 integration namespace

---

### 当前优先级

在当前阶段，优先级大致如下：

1. **语义正确性**
   - 数据结构统一
   - 缓存失效规则正确
   - 调度与依赖链路正确

2. **结构收敛**
   - Session / SegmentManager / Renderer 边界清晰
   - 插件边界清晰
   - 类型与实现一致

3. **性能优化**
   - 在语义稳定后，再针对图处理、依赖查询、缓存结构做优化

---

### 非目标

Quincunx 当前不是：

- 一个完整的歌声合成编辑器
- 一个 DAW
- 一个 UI 框架
- 一个训练框架
- 一个特定模型的实现

这些都属于 Quincunx 之上的 DomainApp 或工具链范畴。

---

### 备注

当前阶段属于 **WIP / refactor-driven design**：

- 先让管线真实跑起来
- 再用实际需求反推抽象边界
- 在保证方向正确的前提下逐步稳定 API

因此近期代码可能比最终设计更“过渡态”，这是预期内的。
