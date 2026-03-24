defmodule Quincunx.Renderer.Planner do
  @moduledoc """
  Aligns compiled `Segment` bundles into a barrier-synchronized execution pipeline.

  Transforms the output of `Compiler.compile_to_recipes/1` into a `Plan` structure
  where bundles sharing the same topological depth are grouped into `Stage`s.
  Tasks within a stage run in parallel; stages execute sequentially.
  """
  alias Quincunx.Compiler
  alias Quincunx.Editor.Segment
  alias Quincunx.Compiler.RecipeBundle

  defmodule Stage do
    @moduledoc """
    A single execution barrier in the plan.

    Contains all `RecipeBundle` tasks that share the same topological depth.
    These tasks are independent and can be executed concurrently.
    The next stage will only begin after all tasks in this stage complete.
    """

    @type task_def :: {Segment.id(), RecipeBundle.t()}
    @type t :: %__MODULE__{
            index: non_neg_integer(),
            tasks: [task_def()]
          }
    defstruct [:index, tasks: []]
  end

  defmodule Plan do
    @moduledoc """
    An ordered sequence of stages forming the complete execution strategy.

    Acts as the input to `Dispatcher.dispatch/3`. The `total_tasks` field
    provides a quick summary for progress tracking and logging.
    """

    @type t :: %__MODULE__{
            stages: [Stage.t()],
            total_tasks: non_neg_integer()
          }
    defstruct [:stages, total_tasks: 0]

    def new(stages) do
      total_tasks = Enum.reduce(stages, 0, &(&2 + length(&1.tasks)))

      %__MODULE__{stages: stages, total_tasks: total_tasks}
    end
  end

  @spec build([Segment.t()] | [{Segment.id(), [RecipeBundle.t()]}]) ::
          {:error, any()} | {:ok, Plan.t()}
  def build(segments_or_compiled_pairs)

  def build([%Segment{} | _] = segments) do
    with {:ok, compiled_pairs} <- Compiler.compile_to_recipes(segments) do
      stages = align_stages(compiled_pairs)
      {:ok, Plan.new(stages)}
    end
  end

  def build(compiled_pairs) do
    stages = align_stages(compiled_pairs)

    {:ok, Plan.new(stages)}
  end

  # inputs => [{seg_id_1, [bundle_A, bundle_B]}, {seg_id_2, [bundle_C]}]
  defp align_stages(compiled_pairs) do
    compiled_pairs
    |> Enum.flat_map(fn {seg_id, bundles} ->
      bundles
      |> Enum.with_index()
      |> Enum.map(fn {bundle, stage_idx} -> {stage_idx, {seg_id, bundle}} end)
    end)
    |> Enum.group_by(fn {idx, _task} -> idx end, fn {_idx, task} -> task end)
    |> Enum.sort_by(fn {idx, _tasks} -> idx end)
    |> Enum.map(fn {index, tasks} -> %Stage{index: index, tasks: tasks} end)
  end
end
