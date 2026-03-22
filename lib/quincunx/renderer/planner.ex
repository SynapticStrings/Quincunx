defmodule Quincunx.Renderer.Planner do
  @moduledoc """
  Aligning `Quincunx.Segment`s into pipeline batch.
  """
  alias Quincunx.Compiler
  alias Quincunx.Editor.Segment
  alias Quincunx.Compiler.RecipeBundle

  defmodule Stage do
    @type task_def :: {Segment.id(), RecipeBundle.t()}
    @type t :: %__MODULE__{
            index: non_neg_integer(),
            tasks: [task_def()]
          }
    defstruct [:index, tasks: []]
  end

  defmodule Plan do
    @type t :: %__MODULE__{
            stages: [Stage.t()],
            total_tasks: non_neg_integer()
          }
    defstruct [:stages, total_tasks: 0]

    def new(stages) do
      total_tasks = Enum.reduce(stages, 0, fn s, acc -> acc + length(s.tasks) end)

      %__MODULE__{stages: stages, total_tasks: total_tasks}
    end
  end

  @spec build([Segment.t()]) :: {:error, any()} | {:ok, Plan.t()}
  def build(segments) do
    with {:ok, compiled_pairs} <- Compiler.compile_to_recipes(segments) do
      stages = align_stages(compiled_pairs)
      {:ok, Plan.new(stages)}
    end
  end

  # Input: [{seg_id_1, [bundle_A, bundle_B]}, {seg_id_2, [bundle_C]}]
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
