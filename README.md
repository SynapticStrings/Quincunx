# Quincunx

A lightweight orchestration core for real-time incremental generation, with parametric curve modulation and pluggable calculate backends.

Quincunx is originally designed to be embedded inside larger systems such as vocal editors (OpenUTAU-like) or live singing engines. It acts as the bridge between abstract musical data (Notes, Phonemes, Curves) and the concrete execution graph managed by [Orchid](https://hex.pm/packages/orchid).

*Although the initial vision is to implement an interactive singing synthesis editor, Quincunx remains domain-agnostic and does not introduce domain-specific dependencies.*

## Features

- Real-time Incremental Rendering
- Parametric Curve Modulation
- Automatic Deterministic Caching (via ETS & OrchidStratum)
- Heterogeneous Device Scheduling (Topology Tearing)
- Seamless OTP/GenServer Integration

## Define Scope

Quincunx is:

* An orchestration core for application
* Backend-agnostic (Python / ONNX / HTTP service)
* Designed for fine-grained modulation
* Embeddable inside BEAM systems

And Quincunx isn't:

* A singing synthesizer editor
* A DAW
* A GUI framework
* A training toolkit
* An acoustic model implementation

---

<details open>
<summary><b>Architecture & Key Concepts (Click to expand)</b></summary>

### Granularity Control of Incremental Generation

In Quincunx, the indivisible unit of incremental computation is the **Segment**.
Media data (like music or animation) usually exhibits strong temporal and spatial locality. Modifying a single measure of notes shouldn't trigger a full-song re-render.

*   **Pure Data Topology (Lily Graph)**: Each Segment uses a deterministic Directed Acyclic Graph (DAG) to describe computational steps.
*   **Compilation & Alignment**: Before execution, Quincunx compiles graphs from multiple Segments into standardized `Orchid.Recipe` sets, utilizing **Stages as execution barriers** to push data flow forward safely and in parallel.

### Human Intervention vs. Generative Models

Because the base Lily Graph is immutable, Quincunx introduces a **History State Machine**:
*   User interventions do not permanently mutate the base topology. Instead, they are pushed onto an undo/redo stack as `Operation`s (e.g., `{:set_intervention, port, data}`).
*   During incremental rendering, the `Compiler` treats these interventions as constant parameters, performing **Late Binding** into the execution context. 

### Deterministic Caching Mechanism

When a node executes, the system calculates a fingerprint ( $\mathrm{StepKey} = \mathrm{SHA256}(\mathrm{Impl} \parallel \mathrm{InputHashes} \parallel \mathrm{SortedOpts})$ ). A cache hit immediately swaps heavy computations with lightweight memory references.

Unlike global cache pools, Quincunx provisions isolated `Storage` per document/session leveraging BEAM process semantics. **When a document process terminates, the VM instantly garbage collects the associated cache.**

### Heterogeneous Device Scheduling

Quincunx manages heterogeneous routing via **Cluster (Color Painting)**. Modifying the `Cluster` declaration will trigger **Topology Tearing**: Dependent nodes belonging to different clusters are automatically split into separate `Orchid.Recipe`s. This allows the host application to dispatch heavy tensors to dedicated Python logic while keeping lightweight data transformations local.

### The Execution Triad
1. **Planner (Pure Functional)**: Resolves segment histories, compiles them, and outputs a deterministic plan grouped by `Stage`s.
2. **Dispatcher (OTP Coordinator)**: An asynchronous state machine that executes tasks stage by stage, maintaining barrier-synchronization.
3. **Worker (Stateless Runner)**: Wraps `Orchid.run/3`, resolves dependencies from the `Blackboard`, and applies cache bypassing.
</details>

---

## Quick Start

### OTP Version (Recommended)

Quincunx provides a robust, session-based `GenServer` structure capable of isolated caching and state orchestration.

```elixir
alias Quincunx.Session
alias Quincunx.Editor.Segment

# 1. Start an isolated session process
{:ok, pid} = Session.start(:my_project_session)

# 2. Assume you have a compiled segment, push interventions (e.g., overriding AI configs)
apply_op = {:set_intervention, {:port, :model_node, :pitch}, :override, curve_data}
GenServer.cast(pid, {:apply_operation, segment_id, apply_op})

# 3. Trigger the dispatch phase to calculate everything in parallel
# The Session will automatically compile changes, apply cluster splitting, bypass caches,
# and write results back to the blackboard.
:ok = GenServer.call(pid, :dispatch)
```

### Non-OTP Version (Pure Functional)

If you prefer managing the lifecycle manually:

```elixir
alias Quincunx.Session.Segment
alias Quincunx.Session.Renderer.{Planner, Dispatcher, Blackboard}

# 1. User applies an operation
dirty_segment = Segment.apply_operation(segment, {:set_input, port_key, curve_data})

# 2. Planner compiles and aligns segments
{:ok, plan} = Planner.build([dirty_segment])

# 3. Mount Blackboard
blackboard = Blackboard.new(:my_vocal_session)

# 4. Dispatch parallel rendering
{:ok, new_blackboard} = Dispatcher.dispatch(plan, blackboard)
```

---

## Extensibility & Configuration

Quincunx is decoupled from domain logic via **Orchid's Baggage and Hooks**. You can easily configure backends, handle error telemetry, or inject custom domain logic without forking Quincunx.

### Injecting Hooks (e.g., Custom Parameter Offsets)

Want to add custom audio-offsetting or error handling hooks? Pass `orchid_executor_and_opts` and `orchid_baggage` during the Dispatcher or Session call:

```elixir
# Example: Injecting your custom Override Hook and specific Baggage parameters
orchid_opts = [
  orchid_executor_and_opts: {Orchid.Executor.Parallel, [
    hooks: [Orchid.Hook.Override]
  ]},
  orchid_baggage: [
    override: %{/* global override map */},
    offset: %{/* global offset map */}
  ]
]

# When using Session (OTP GenServer):
GenServer.call(:my_session, {:dispatch, orchid_opts})

# When using Dispatcher directly:
Dispatcher.dispatch(plan, blackboard, orchid_opts)
```

Your `Orchid.Runner.Hook` can then intercept the execution flow, process these Baggage variables, and seamlessly integrate into Quincunx's lifecycle.