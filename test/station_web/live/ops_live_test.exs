defmodule StationWeb.OpsLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Dispatcher
  alias Station.OpsPanel

  setup %{conn: conn} do
    password = Application.fetch_env!(:station, :ops_password)
    credentials = Plug.BasicAuth.encode_basic_auth("ops", password)
    %{conn: put_req_header(conn, "authorization", credentials)}
  end

  test "the panel is not reachable without the password" do
    assert build_conn() |> get(~p"/ops") |> response(401)
  end

  test "a traffic level is one press", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#traffic-quiet") |> render_click()

    assert OpsPanel.freighters() == OpsPanel.traffic_levels().quiet
    assert Dispatcher.fleet().freighters == OpsPanel.traffic_levels().quiet
    assert render(view) =~ "freighter_01"
  end

  test "an exact number is a form, and nonsense is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view
    |> form("#traffic-count-form", traffic: %{count: "2"})
    |> render_submit()

    assert OpsPanel.freighters() == 2

    view
    |> form("#traffic-count-form", traffic: %{count: "500"})
    |> render_submit()

    assert OpsPanel.freighters() == 2
  end

  test "clearing the warehouse empties the shelf and the queue, not the board", %{conn: conn} do
    [container] = Station.Cargo.build_hold("ice", 1)
    Station.Warehouse.accept("nostromo", container)
    :sys.get_state(Station.Warehouse)
    assert Station.Metrics.get(:stored) == 1

    pid = Process.whereis(Station.Warehouse)
    {:ok, view, _html} = live(conn, ~p"/ops")
    view |> element("#clear-warehouse") |> render_click()

    assert Process.whereis(Station.Warehouse) != pid
    assert Station.Metrics.get(:stored) == 0
    assert %{"ice" => 0} = Station.Warehouse.shelf()
    assert %{containers: 1} = Station.Leaderboard.get("nostromo")
  end

  test "clearing with a crew on empties the clerks' mailboxes too", %{conn: conn} do
    OpsPanel.set_clerks(2)
    before = Station.InspectionCrew.on_shift() |> Tuple.to_list() |> Enum.map(&Process.whereis/1)
    Enum.each(before, &:sys.suspend/1)

    for container <- Station.Cargo.build_hold("ice", 4),
        do: Station.Warehouse.accept(nil, container)

    :sys.get_state(Station.Warehouse)
    Station.Watchdog.sample()
    assert Station.Warehouse.stats().backlog == 4

    {:ok, view, _html} = live(conn, ~p"/ops")
    view |> element("#clear-warehouse") |> render_click()
    Station.Watchdog.sample()

    assert Station.Warehouse.stats().backlog == 0
    assert Station.InspectionCrew.size() == 2

    after_pids =
      Station.InspectionCrew.on_shift() |> Tuple.to_list() |> Enum.map(&Process.whereis/1)

    assert Enum.all?(after_pids, &(&1 not in before))
  end

  test "clerks are a button or a number, and one clerk is the single clerk", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> form("#clerks-form", clerks: %{count: "3"}) |> render_submit()
    assert OpsPanel.warehouse_mode() == :inspection_crew
    assert Station.InspectionCrew.size() == 3
    assert OpsPanel.clerks() == 3

    view |> element("#clerks-one") |> render_click()
    assert OpsPanel.warehouse_mode() == :single_clerk
    assert Station.InspectionCrew.size() == 0

    # The count is remembered: the mode switch alone brings the same crew back.
    OpsPanel.set_warehouse_mode(:inspection_crew)
    assert Station.InspectionCrew.size() == 3

    view |> element("#clerks-default") |> render_click()
    assert Station.InspectionCrew.size() == OpsPanel.default_clerks()
  end

  test "haulers are a multiplier button or an exact number", %{conn: conn} do
    baseline = Application.fetch_env!(:station, :haulers)
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> form("#haulers-form", haulers: %{count: "5"}) |> render_submit()
    assert OpsPanel.haulers() == 5
    assert Dispatcher.fleet().haulers == 5

    view |> element("#haulers-x4") |> render_click()
    assert OpsPanel.haulers() == baseline * 4

    view |> form("#haulers-form", haulers: %{count: "0"}) |> render_submit()
    assert Dispatcher.fleet().haulers == 0
  end

  test "both paces are a number in milliseconds, within bounds", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> form("#freighter-pace-form", freighter_pace: %{ms: "800"}) |> render_submit()
    assert OpsPanel.freighter_interval_ms() == 800

    view |> form("#hauler-pace-form", hauler_pace: %{ms: "2500"}) |> render_submit()
    assert OpsPanel.hauler_interval_ms() == 2500

    view |> form("#freighter-pace-form", freighter_pace: %{ms: "5"}) |> render_submit()
    assert OpsPanel.freighter_interval_ms() == 800
  end

  test "the QR codes on the television are a switch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#qr-off") |> render_click()
    refute OpsPanel.show_qr?()

    view |> element("#qr-on") |> render_click()
    assert OpsPanel.show_qr?()
  end

  test "yield is a switch and undock-all is a button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#yield-off") |> render_click()
    refute OpsPanel.yield_to_visitors?()

    view |> element("#yield-on") |> render_click()
    assert OpsPanel.yield_to_visitors?()

    OpsPanel.set_traffic(3)
    view |> element("#clear-freighters") |> render_click()

    assert OpsPanel.freighters() == 0
    assert Dispatcher.fleet().freighters == 0
  end
end
