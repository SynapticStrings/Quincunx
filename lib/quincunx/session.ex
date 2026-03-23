defmodule Quincunx.Session do
  @moduledoc """
  Public API for managing incremental generation sessions.
  """

  @type session :: GenServer.server()

  def start(session_id, opts \\ []) when is_atom(session_id) do
    session_supervisor_spec = %{
      id: session_id,
      start: {Quincunx.Session.InstanceSupervisor, :start_link, [session_id, opts]}
    }

    DynamicSupervisor.start_child(Quincunx.SessionSupervisor, session_supervisor_spec)
  end

  def stop(session_id) do
    case resolve(session_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(Quincunx.SessionSupervisor, pid)
      error -> error
    end
  end

  defp resolve(session_id) do
    case Registry.lookup(Quincunx.SessionRegistry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :session_not_found}
    end
  end
end
