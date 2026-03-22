defmodule Quincunx.Renderer.Planner do
  @moduledoc """
  Aligning `Quincunx.Segment`s into pipeline batch.
  """
  alias Quincunx.Segment
  alias Quincunx.Lily.RecipeBundle

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

  @spec build([Quincunx.Segment.t()]) ::
          {:error, any()} | {:ok, Quincunx.Renderer.Planner.Plan.t()}
  def build(segments) do
    with {:ok, segments_with_recipes} <- Segment.compile_to_recipes(segments) do
      stages = align_stages(segments_with_recipes)

      {:ok, Plan.new(stages)}
    else
      err -> err
    end
  end

  @spec align_stages([Segment.t()]) :: [Stage.t()]
  defp align_stages(compiled_segments) do
    compiled_segments
    |> Enum.flat_map(fn %Segment{id: seg_id, recipe_bundles: recipes} ->
      recipes
      |> Enum.with_index()
      |> Enum.map(fn {bundle, idx} -> {idx, {seg_id, bundle}} end)
    end)
    |> Enum.group_by(fn {idx, _task} -> idx end, fn {_idx, task} -> task end)
    |> Enum.sort_by(fn {idx, _tasks} -> idx end)
    |> Enum.map(fn {index, tasks} -> %Stage{index: index, tasks: tasks} end)
  end
end
