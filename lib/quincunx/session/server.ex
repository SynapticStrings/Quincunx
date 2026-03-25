defmodule Quincunx.Session.Server do
  @moduledoc """
  Provide a GenServer for Session service.
  """
  use GenServer

  require Logger

  alias Quincunx.Session.{Storage, Context}
  alias Quincunx.Session
  alias Quincunx.Editor.Segment
  alias Quincunx.Renderer.Dispatcher

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: Session.server(session_id))
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    storage = if Keyword.get(opts, :enable_cache, true), do: Storage.new(), else: nil

    {:ok, Context.new(session_id, storage)}
  end

  @impl true
  def handle_cast({:add_segment, %Segment{} = segment}, %Context{} = state) do
    case Context.add_segment(state, segment) do
      {:ok, new_state} -> {:noreply, new_state}
      {:already_exist, _seg_id} -> {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:remove_segment, seg_id}, %Context{} = state) do
    {:noreply, Context.remove_segment(state, seg_id)}
  end

  @impl true
  def handle_cast({:apply_operation, seg_id, op}, %Context{} = state) do
    case Context.operate(state, seg_id, op) do
      %Context{} = new_state -> {:noreply, new_state}
      {:seg_not_exist, ^seg_id} -> {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:dispatch, dispatch_opts}, %Context{} = state) do
    case Context.dispatch_to_plans(state) do
      {_legacy_state, {:error, _}} = _err ->
        {:noreply, state}

      {%Context{} = new_state, plan} ->
        cancel_pending_task(state)

        task = start_render_task(new_state, plan, dispatch_opts)
        {:noreply, %{new_state | render_tasks: task}}
    end
  end

  @impl true
  def handle_call(:inspect, _from, %Context{} = state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_info({ref, {:ok, new_board}}, %Context{render_tasks: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    {:noreply, %{state | blackboard: new_board, render_tasks: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %Context{render_tasks: %{ref: ref}} = state
      ) do
    if reason != :killed do
      require Logger
      Logger.error("Engine crashed!\n\nReason: #{inspect(reason)}")
    end

    {:noreply, %{state | render_tasks: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Cought unknown message:\n\n#{inspect(msg)}")

    {:noreply, state}
  end

  ## Private Helpers

  defp cancel_pending_task(%Context{render_tasks: nil}), do: :ok

  defp cancel_pending_task(%Context{render_tasks: %{pid: pid}} = state) do
    Task.Supervisor.terminate_child(Session.task_sup(state.session_id), pid)
  end

  defp start_render_task(%Context{} = state, plan, opts) do
    Task.Supervisor.async_nolink(
      Session.task_sup(state.session_id),
      fn -> Dispatcher.dispatch(plan, state.blackboard, opts) end
    )
  end
end
