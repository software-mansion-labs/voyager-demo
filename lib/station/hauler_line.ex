defmodule Station.HaulerLine do
  @moduledoc """
  The consumers. Deliberately too few of them, until ops says otherwise.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 100)
end
