# [WIP] Quincunx

> [!IMPORTANT]
>
> To ensure development efficiency, documentation and comments will be in Chinese currently.
> Once the API is comsolidate, I'll translate docs and comments into English.

用于存在外部数据介入的增量生成任务的轻量级编排核心。

*尽管最初的愿景是实现一个交互式歌唱合成编辑器，但 Quincunx 仍然保持领域无关性，并且不会引入特定领域的依赖项。*

## 特征

* 整合 OTP/GenServer 服务（基于 [OrchidSymbiont](https://github.com/SynapticStrings/OrchidSymbiont)）
* 基于 [OrchidStratum](https://github.com/SynapticStrings/OrchidStratum) 的自动确定性缓存（可以实现基于 `Segment` 的增量生成）
* 异构设备调度的潜能

## 范畴

Quincunx 是：

* 一个用于应用的调度核心
* 使用服务无关（Python / NIF / ONNX / HTTP 服务）
* 专为需要人类的精细调制/介入的任务而设计
* 嵌入在 BEAM 系统之中

Quincunx 不是：

* 歌声合成编辑器
* DAW
* UI 框架
* 训练集合
* 声学模型实现

## 开发进度

- [x] 可运行任务
- [ ] 整合缓存并运行
- [ ] 工程可以被导出/加载为文件
- [ ] 一点面向编辑器的小改动
