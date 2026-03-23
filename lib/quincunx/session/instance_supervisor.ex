defmodule Quincunx.Session.InstanceSupervisor do
  use Supervisor

  def start_link(session_id, opts) do
    name = Module.concat([session_id, Supervisor])
    Supervisor.start_link(__MODULE__, {session_id, opts}, name: name)
  end

  @impl true
  def init({session_id, opts}) do
    children = [
      {Orchid.Symbiont.Runtime, session_id: session_id},
      {Task.Supervisor, name: Module.concat([session_id, RenderTaskSupervisor])},
      {Quincunx.Session.Server, Keyword.put(opts, :session_id, session_id)}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
