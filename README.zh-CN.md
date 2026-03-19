# ⁙Quincunx⁙

针对异质性批量数据的增量生成引擎（原 QyCore）。

*尽管设计的愿景为实现交互式歌声合成编辑器，但 Quincunx 保持领域无关，不会引入领域相关的依赖以及代码。*

## 关键点

### 增量生成的粒度控制

在 Quincunx 中，增量计算的最小不可分割单元被称为 **Segment（片段）**。
音乐、视频或动画数据通常具有明显的时间空间局部性（例如：修改一小节的音符，不应导致整首歌重新渲染）。

*   **纯数据拓扑 (Lily Graph)**：每个 Segment 内部利用纯粹的数学有向无环图（DAG）描述计算步骤（如：`Note -> Acoustic Model -> Vocoder`）。
*   **编译与对齐 (Compiler & RenderTask)**：Quincunx 会在执行前，将多个 Segment 的图结构编译为一组组标准的 `Orchid.Recipe`。执行引擎以**阶段（Stage）作为屏障（Barrier）**，批量且并行地推进所有片段的设计流转，确保数据流的生命周期精确可控。

### 用户修改覆盖上游模型生成的情况

在交互式编辑器中，典型的场景是：生成式人工智能（大模型）输出了一个基础曲线或参数，但用户需要在这个基础上进行**手绘覆盖（Override）或偏移（Offset）**。

由于底层图是纯粹不可变的，Quincunx 引入了基于撤销/重做栈的 **`History` 状态机**：

*   用户的任何干预不会直接破坏底层拓扑，而是存储为 `Operation`（如 `{:override, port, data}`）。
*   在每次触发增量渲染时，`Compiler` 会将被选中的历史操作（Interventions）作为常数参数（Constant Inputs）**晚期绑定（Late Binding）** 到即将执行的执行器上下文中。
*   这种设计实现了**模型输出与人类干预的完美隔离**，既保留了重排版的能力，又支持无损撤销。

### 增量生成的缓存机制

高性能的增量生成高度依赖缓存。Quincunx 底层无缝融合了 **OrchidStratum**（一个基于内容寻址的缓存中间件）：

1.  **内容哈希 (Content-Addressable)**：当任何一个计算节点（Step）准备执行时，系统会计算其输入数据、执行体本身以及关键参数的 SHA-256 签名（即 $\mathrm{StepKey}$）。如果命中，将直接使用轻量级的引用指针（Ref）绕过计算，实现极致加速。
2.  **基于 Session 的强隔离 (Session Storage)**：不同于全局缓存池，Quincunx 为工程级别定义了 `Storage`。利用 BEAM 虚拟机的进程特性，每个打开的文档/工程进程持有一对独立的（未命名）ETS 内存表。**文档关闭即意味着所属进程销毁，底层虚拟机会瞬间回收相关缓存内存，做到零泄漏、零串扰。**

### 异构设备的并行策略考虑

面对现代工作流（混合了本地 CPU 逻辑、强 VRAM 依赖的 GPU 推理、乃至通过 HTTP 调用的云端服务），必须进行物理层面的隔离投递。

Quincunx 通过 **`Cluster` (着色分簇)** 应对异构设备的调度：

*   **按需着色**：在图编译阶段，节点和边会被根据用户声明或上下游依赖推导，标记上特定的簇名（如 `:cpu_cluster`, `:gpu_cluster`）。
*   **拓扑切割**：相互依赖但隶属不同簇的节点，会被自动撕裂成多段独立的 `Orchid.Recipe`。
*   这种机制允许宿主系统在派发任务时，将重计算片段丢给专门的 Python/NIF 异构工作节点，而将轻量级的拼装操作留在本地 Erlang 调度器中。

## 进程模型与核心对象

- `Quincunx.Session.Segment`： 承载单个上下文片段的核心数据结构。它持有基础的计算图（基底）、针对此片段的用户编辑操作栈（History），以及在最近一次编译中缓存的配方引用。它是增量执行队列中的第一公民。
- `Quincunx.Session.Storage`： 存储生命周期管理器。通常由宿主的上层建筑（如一个具体的文档 GenServer）在 `init/1` 时调用 `new/0` 颁发。它返回当前会话专用的 Stratum（缓存策略）适配器凭证。配合 `RenderTask` 时，保证数据的生命周期与会话进程强绑定。
- `Quincunx.Session.Renderer.RenderTask`： 无状态的批量渲染流水线（Pipeline）。它接收一组需要更新的 `Segment` 和前驱输出积累的 `Blackboard`，拉平所有的执行阶段（Align Stages），应用由 `Storage` 提供的旁路缓存中间件，随后通过高并发流 (`Task.async_stream`) 压榨多核算力，最终向外部返回一个新的黑板全貌。
- `Quincunx.Session.Renderer.Blackboard`： 阶段执行之间的“动态黑板（运行时数据总线）”。在前一个 Stage 完成后，所有输出结果会被脱水或直接挂载到黑板上。当下一个阶段启动时，需要的动态依赖（Require Keys）只需通过 `{segment_id, port_name}` 从黑板上检索即可。

## 路线图

- [x] 历史记录
- [x] 基于节点和边声明的 DAG
    - [x] 和 Orchid Recipe 的转换
- [x] 大图分簇编译成多个（串行的） Orchid Recipe
- [x] 缓存机制的并入
- [ ] 一个完整的 OTP 组件
    - 可恢复的 Orchid Recipe
- [ ] 序列化与反序列化
- [ ] 任务中断与恢复
- [ ] 插件
