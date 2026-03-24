defmodule Quincunx.SessionRegistry do
  @moduledoc false
  # Inspired by Oban's Registry design.

  def child_spec(_init_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @doc "Build a vi tuple."
  def via(sesion_id, role \\ nil), do: {:via, Registry{__MODULE__, key(session_id, role)}}

  defp key(session_id, nil), do: session_id
  defp key(session_id, role), do: {session_id, role}
end
