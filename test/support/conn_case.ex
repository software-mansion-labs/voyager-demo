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
    end
  end

  setup _tags do
    Station.DockingBay.clear()
    Station.Warehouse.flush()
    Station.Leaderboard.reset()
    Station.Metrics.reset()
    Station.OpsPanel.set_warehouse_mode(:single_clerk)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A connection carrying a docked ship, the way a registered visitor has one."
  def with_ship(conn, name \\ "Nostromo", cargo \\ "ice") do
    {:ok, registered} = Station.DockingBay.dock(name, cargo)

    conn = Plug.Test.init_test_session(conn, ship: Station.ShipNames.to_slug(registered))
    {conn, registered}
  end
end
