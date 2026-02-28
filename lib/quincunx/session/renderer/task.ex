defmodule Quincunx.Session.Renderer.Task do
  alias Quincunx.Session.Segment

  @type blackboard :: %{
          optional({Segment.id(), Quincunx.Session.Segment.Graph.Portkey.t()}) => Orchid.Param.t() | any()
        }

  @doc """
  Executes the batch of segments.
  """
  @spec run([Segment.t()], keyword()) :: {:ok, blackboard()} | {:error, any()}
  def run(segments, opts \\ []) do
    # 1. Compile and Bind
    with {:ok, compiled_segments} <- Segment.compile_to_recipes(segments) do
      # 2. Align Stages (Transpose)
      # From: [SegA([R1, R2]), SegB([R1, R2])]
      # To:   [[{SegA, R1}, {SegB, R1}], [{SegA, R2}, {SegB, R2}]]
      pipeline_stages = align_stages(compiled_segments)

      # 3. Execute Stage by Stage (Barrier)
      initial_board = %{}

      Enum.reduce_while(pipeline_stages, {:ok, initial_board}, fn stage_batch, {:ok, board} ->
        case execute_stage_barrier(stage_batch, board, opts) do
          {:ok, new_board} -> {:cont, {:ok, new_board}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp align_stages(segments) do
    segments
    |> Enum.map(fn seg ->
      Enum.map(seg.compiled_recipes, &{seg.id, &1})
    end)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  # --- Barrier Logic ---

  defp execute_stage_barrier(batch, blackboard, opts) do
    # Configuration
    concurrency = opts[:concurrency] || System.schedulers_online()
    timeout = opts[:timeout] || 30_000

    # Parallel Execution via Task.async_stream
    # This is where the 100 segments run concurrently.
    stream =
      Task.async_stream(
        batch,
        fn {seg_id, recipe} ->
          process_segment_recipe(seg_id, recipe, blackboard)
        end, max_concurrency: concurrency, timeout: timeout, ordered: false)

    # Collect Results (Reduce)
    Enum.reduce_while(stream, {:ok, blackboard}, fn
      {:ok, {:ok, seg_id, outputs}}, {:ok, acc_board} ->
        # Merge outputs back to blackboard for the next stage
        updated_board = merge_to_blackboard(acc_board, seg_id, outputs)
        {:cont, {:ok, updated_board}}

      {:ok, {:error, reason}}, _ ->
        {:halt, {:error, reason}}

      {:exit, reason}, _ ->
        {:halt, {:error, {:task_exit, reason}}}
    end)
  end

  # --- Worker Logic (Running inside Task) ---

  defp process_segment_recipe(seg_id, recipe, blackboard) do
    # 1. Resolve Requires (Dynamic Inputs from Blackboard)
    # The `recipe.requires` field (from Lily) tells us what ports we need from previous stages.
    # Note: Orchid.Recipe struct doesn't standardly have :requires field,
    # assuming Lily added it to recipe.opts or we pass it alongside.
    # Let's assume Lily put `requires` list in `recipe.opts[:requires]`.
    required_keys = Keyword.get(recipe.opts, :requires, [])

    dynamic_inputs =
      Enum.map(required_keys, fn port_name ->
        case Map.get(blackboard, {seg_id, port_name}) do
          %Orchid.Param{} = param -> param

          # Determine type? Orchid params need types.
          # For intermediate data, :any or :tensor is usually fine.
          val ->
            port_name
            |> Quincunx.Session.Segment.Graph.Portkey.to_orchid_key()
            |> Orchid.Param.new(:any, val)
        end
      end)

    # 2. Mix with Static Interventions
    # Assuming `Compiler.bind_interventions` stored static inputs
    # into `recipe.opts[:initial_params]` or similar.
    # If Lily compiled them directly into the recipe steps, we just pass dynamic inputs.
    # Let's assume we merge dynamic inputs with whatever Lily prepared.
    # But usually, Orchid.run accepts `initial_params`.

    # If Lily embedded interventions into recipe steps (as constant inputs),
    # we only supply dynamic inputs.

    # 3. Run Orchid
    # We use Serial executor inside the task to avoid spawning more processes.
    run_opts = [
      executor_and_opts: {Orchid.Executor.Serial, []},
      # Pass segment ID in baggage for logging/debugging
      baggage: [segment_id: seg_id]
    ]

    case Orchid.run(recipe, dynamic_inputs, run_opts) do
      {:ok, results} ->
        {:ok, seg_id, results}

      {:error, reason} ->
        {:error, {:orchid_run_failed, seg_id, reason}}

      other ->
        {:error, {:unexpected_return, other}}
    end
  end

  # --- Helpers ---

  defp merge_to_blackboard(board, seg_id, outputs) do
    # outputs is a map of %{name => %Param{}}
    Enum.reduce(outputs, board, fn {name, param}, acc ->
      # We strip the Param wrapper and store raw payload to save memory/complexity
      Map.put(acc, {seg_id, name}, Orchid.Param.get_payload(param))
    end)
  end
end
