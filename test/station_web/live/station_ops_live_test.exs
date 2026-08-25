defmodule StationWeb.StationOpsLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Cargo
  alias Station.Events
  alias Station.Warehouse

  test "the television names every docked ship", %{conn: conn} do
    {:ok, _} = Station.DockingBay.dock("Nostromo", "ore")
    {:ok, _} = Station.DockingBay.dock("Rocinante", "ice")

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "ship_nostromo"
    assert html =~ "ship_rocinante"
    assert html =~ "station_leaderboard"
  end

  test "the board only counts visitors, never the background fleet", %{conn: conn} do
    [container] = Cargo.build_hold("ore", 1)

    Warehouse.accept("nostromo", container)
    Warehouse.accept(nil, container)
    :sys.get_state(Warehouse)

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "nostromo"
    assert Station.Leaderboard.size() == 1
  end

  test "the log collapses a line that repeats instead of scrolling it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tv")

    for _ <- 1..3, do: Events.emit(:test, "WAREHOUSE OVER CAPACITY", :warning)
    # The LiveView has to process all three broadcasts before we look.
    _ = :sys.get_state(view.pid)

    assert render(view) =~ "x3"
  end
end
