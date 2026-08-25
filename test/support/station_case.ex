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
    Station.DockingBay.clear()
    Station.Warehouse.flush()
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
end
