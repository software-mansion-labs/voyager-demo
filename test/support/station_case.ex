defmodule Station.Case do
  @moduledoc """
  Case template for tests that touch the running station.

  The station is a singleton - one warehouse, one docking bay, one leaderboard -
  so these tests are serial and reset the shared state between them rather than
  pretending each one gets its own.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Station.Case
    end
  end

  setup do
    Station.OpsPanel.set_traffic(0)
    Station.OpsPanel.set_yield_to_visitors(false)
    Station.DockingBay.clear()
    # Flush is a cast; wait for it, or a container still in the mailbox lands
    # on the freshly zeroed counters of the next test.
    Station.Warehouse.flush()
    _ = :sys.get_state(Station.Warehouse)
    Station.Leaderboard.reset()
    Station.Metrics.reset()
    Station.OpsPanel.set_warehouse_mode(:single_clerk)
    :ok
  end

  @doc "Blocks until the warehouse has worked through its mailbox."
  def settle do
    :sys.get_state(Station.Warehouse)
    :ok
  end

  @doc "Blocks until the dispatcher has staffed the fleet to what ops asked for."
  def dispatched do
    :sys.get_state(Station.Dispatcher)
    :ok
  end
end
