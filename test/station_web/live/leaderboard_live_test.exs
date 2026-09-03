defmodule StationWeb.LeaderboardLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Cargo
  alias Station.Warehouse

  test "the board only counts visitors, never the background fleet", %{conn: conn} do
    [container] = Cargo.build_hold("ore", 1)

    Warehouse.accept("nostromo", container)
    Warehouse.accept(nil, container)
    :sys.get_state(Warehouse)

    {:ok, _view, html} = live(conn, ~p"/leaderboard")

    assert html =~ "station_leaderboard"
    assert html =~ "nostromo"
    assert Station.Leaderboard.size() == 1
  end
end
