defmodule StationWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  The station itself is a singleton - one warehouse, one docking bay, one
  leaderboard - so these tests run serially and reset the shared state between
  them rather than pretending each one gets its own.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint StationWeb.Endpoint

      use StationWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import StationWeb.ConnCase
      import Station.Case, only: [settle: 0, dispatched: 0]
    end
  end

  setup _tags do
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

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A connection carrying a docked ship, the way a visitor who scanned the code has one."
  def with_ship(conn) do
    {:ok, registered} = Station.DockingBay.dock()

    conn = Plug.Test.init_test_session(conn, ship: Station.ShipNames.to_slug(registered))
    {conn, registered}
  end
end
