defmodule Quincunx.Session do
  @moduledoc """
  Public API for managing incremental generation sessions.
  """

  alias Quincunx.Session.Server

  @type session :: GenServer.server()

  def start(session_id, opts \\ []) do
    DynamicSupervisor.start_child(
      Quincunx.SessionSupervisor,
      {Server, Keyword.put(opts, :session_id, session_id)}
    )
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
