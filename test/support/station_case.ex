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
    Station.Hangar.clear()
    # Drain everything in flight - warehouse, clerks, warehouse again - then
    # flush and drain once more, or a container still with a clerk lands on the
    # freshly zeroed counters of the next test.
    Station.Case.settle()
    Station.Warehouse.flush()
    Station.Case.settle()
    Station.Leaderboard.reset()
    Station.Metrics.reset()
    Station.OpsPanel.set_clerks(1)
    Station.OpsPanel.set_show_qr(true)
    Station.OpsPanel.set_haulers(Application.fetch_env!(:station, :haulers))

    Station.OpsPanel.set_freighter_interval(
      Application.fetch_env!(:station, :freighter_interval_ms)
    )

    Station.OpsPanel.set_hauler_interval(Application.fetch_env!(:station, :hauler_interval_ms))
    :ok
  end

  @doc """
  Blocks until every container in flight is stored: through the warehouse,
  through each clerk on shift, and back through the warehouse.
  """
  def settle do
    :sys.get_state(Station.Warehouse)

    for clerk <- Station.InspectionCrew.workers(), pid = Process.whereis(clerk), is_pid(pid) do
      :sys.get_state(pid)
    end

    :sys.get_state(Station.Warehouse)
    :ok
  end

  @doc "Blocks until the dispatcher has staffed the fleet to what ops asked for."
  def dispatched do
    :sys.get_state(Station.Dispatcher)
    :ok
  end
end
