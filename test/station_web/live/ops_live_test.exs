defmodule StationWeb.OpsLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.DockingBay
  alias Station.InspectionCrew
  alias Station.OpsPanel

  setup %{conn: conn} do
    %{conn: ops_auth(conn), token: Application.fetch_env!(:station, :ops_token)}
  end

  test "the panel is not reachable without the password", %{token: token} do
    assert build_conn() |> get(~p"/ops/#{token}") |> response(401)
  end

  test "the panel is not reachable under a guessed path", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/ops/not-the-token") end
  end

  test "the two switches that are the demo", %{conn: conn, token: token} do
    {:ok, view, _html} = live(conn, ~p"/ops/#{token}")

    view
    |> element("button", "INSPECTION CREW")
    |> render_click()

    assert OpsPanel.warehouse_mode() == :inspection_crew
    assert InspectionCrew.size() > 0

    view
    |> element("button", "SINGLE CLERK")
    |> render_click()

    assert OpsPanel.warehouse_mode() == :single_clerk
    assert InspectionCrew.size() == 0
  end

  test "haulers are a staff control, not a code change", %{conn: conn, token: token} do
    {:ok, view, _html} = live(conn, ~p"/ops/#{token}")

    render_click(view, "haulers", %{"factor" => "4"})
    assert OpsPanel.hauler_boost() == 4
  end

  test "ops can pull a ship that should not be on the screen", %{conn: conn, token: token} do
    {:ok, name} = DockingBay.dock("Nostromo", "ice")
    ref = Process.monitor(Process.whereis(name))

    {:ok, view, html} = live(conn, ~p"/ops/#{token}")
    assert html =~ to_string(name)

    render_click(view, "remove_ship", %{"ship" => to_string(name)})

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert DockingBay.list() == []
  end

  test "restarting the warehouse keeps the leaderboard", %{conn: conn, token: token} do
    Station.Leaderboard.record("nostromo", "ore", 5)
    pid = Process.whereis(Station.Warehouse)
    ref = Process.monitor(pid)

    {:ok, view, _html} = live(conn, ~p"/ops/#{token}")
    render_click(view, "restart_warehouse")

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert %{containers: 5} = Station.Leaderboard.get("nostromo")
  end
end
