defmodule Quincunx.Session.InstanceSupervisor do
  use Supervisor

  def via_tuple(session_id, role) do
    {:via, Registry, {Quincunx.SessionRegistry, {session_id, role}}}
  end

  def start_link(session_id, opts) do
    name = via_tuple(session_id, :instance_sup)

    Supervisor.start_link(__MODULE__, {session_id, opts}, name: name)
  end

  @impl true
  def init({session_id, opts}) do
    children = [
      {OrchidSymbiont.Runtime, session_id: session_id},
      {Task.Supervisor, name: via_tuple(session_id, :task_sup)},
      {Quincunx.Session.Server, Keyword.put(opts, :session_id, session_id)}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
