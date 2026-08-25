defmodule Station.FreighterLine do
  @moduledoc """
  The producers. Many of them, docking, unloading and leaving again.

  Collapsed to a child counter in Voyager by default, so the readable part of
  the tree stays the ships with people attached to them.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100)
end
