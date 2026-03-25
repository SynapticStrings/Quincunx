defmodule Quincunx.Session do
  @moduledoc """
  Public API for managing incremental generation sessions.
  """
  import Quincunx.SessionRegistry

  @type id :: binary()
  @type session :: GenServer.server()

  def start(session_id, opts \\ []) do
    case Registry.lookup(Quincunx.SessionRegistry, instance_sup(session_id, :key)) do
      [{pid, _}] ->
        {:error, {:already_started, pid}}

      [] ->
        session_supervisor_spec = %{
          id: session_id,
          start: {Quincunx.Session.InstanceSupervisor, :start_link, [session_id, opts]}
        }

        DynamicSupervisor.start_child(Quincunx.SessionSupervisor, session_supervisor_spec)
    end
  end

  def stop(session_id) do
    case Registry.lookup(Quincunx.SessionRegistry, instance_sup(session_id, :key)) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Quincunx.SessionSupervisor, pid)
      [] -> {:error, :session_not_found}
    end
  end

  def resolve(session_id) do
    case Registry.lookup(Quincunx.SessionRegistry, server(session_id, :key)) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end

  def instance_sup(session_id), do: via(session_id, :instance_sup)
  def instance_sup(session_id, :key), do: key(session_id, :instance_sup)

  def task_sup(session_id), do: via(session_id, :task_sup)
  # def task_sup_key(session_id), do: key(session_id, :task_sup)

  def server(session_id), do: via(session_id, :server)
  def server(session_id, :key), do: key(session_id, :server)
end
