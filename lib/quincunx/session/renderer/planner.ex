defmodule Quincunx.Session.Renderer.Planner do
  @moduledoc """
  Aligning `Quincunx.Session.Segment`s into pipeline batch.
  """
  alias Quincunx.Session.Segment
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

  @spec build([Quincunx.Session.Segment.t()]) ::
          {:error, any()} | {:ok, Quincunx.Session.Renderer.Planner.Plan.t()}
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
    |> Enum.map(fn %Segment{id: seg_id, compiled_recipes: recipes} ->
      Enum.map(recipes, fn bundle -> {seg_id, bundle} end)
    end)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.with_index()
    |> Enum.map(fn {tasks, index} ->
      %Stage{index: index, tasks: tasks}
    end)
  end
end
