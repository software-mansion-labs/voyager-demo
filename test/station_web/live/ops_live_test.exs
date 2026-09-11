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

  test "ops can undock a visitor's ship from the panel", %{conn: conn} do
    {:ok, name} = Station.DockingBay.dock()
    slug = Station.ShipNames.to_slug(name)
    ref = Process.monitor(Process.whereis(name))

    {:ok, view, html} = live(conn, ~p"/ops")
    assert html =~ to_string(name)

    view |> element("#undock-#{slug}") |> render_click()

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert Station.DockingBay.list() == []
    refute Station.Hangar.parked?(slug)
    refute render(view) =~ to_string(name)
  end

  test "ops can empty every berth at once - visitors, hangar and freighters", %{conn: conn} do
    {:ok, docked} = Station.DockingBay.dock()
    {:ok, parked} = Station.DockingBay.dock()
    parked_slug = Station.ShipNames.to_slug(parked)
    Station.Hangar.park(:sys.get_state(Process.whereis(parked)))
    Station.Ship.undock(parked)
    :ok = OpsPanel.set_traffic(1)
    assert Station.FreighterLine.count() == 1

    {:ok, view, _html} = live(conn, ~p"/ops")
    view |> element("#undock-everyone") |> render_click()
    dispatched()

    assert Process.whereis(docked) == nil
    assert Station.DockingBay.list() == []
    refute Station.Hangar.parked?(parked_slug)
    assert OpsPanel.freighters() == 0
    assert Station.FreighterLine.count() == 0
  end

  test "undocking all visitors leaves the freighters alone", %{conn: conn} do
    {:ok, _first} = Station.DockingBay.dock()
    {:ok, _second} = Station.DockingBay.dock()
    :ok = OpsPanel.set_traffic(1)

    {:ok, view, _html} = live(conn, ~p"/ops")
    view |> element("#undock-visitors") |> render_click()

    assert Station.DockingBay.list() == []
    assert Station.FreighterLine.count() == 1
  end

  test "the hauled counter can be reset to zero from the panel", %{conn: conn} do
    for container <- Station.Cargo.build_hold("ice", 3),
        do: Station.Warehouse.accept(nil, container)

    settle()
    Station.Warehouse.collect(self(), 3)
    settle()
    assert_receive {:cargo_collected, [_, _, _]}
    assert Station.Warehouse.stats().collected == 3
    assert %{"ice" => 3} = Station.Warehouse.collected()

    {:ok, view, html} = live(conn, ~p"/ops")
    assert html =~ "RESET HAULED COUNTER (3)"

    view |> element("#reset-hauled") |> render_click()

    assert Station.Warehouse.stats().collected == 0
    assert %{"ice" => 0} = Station.Warehouse.collected()
    # The shelf is not touched: only the running total of what left.
    assert Station.Metrics.get(:stored) == 0
    assert render(view) =~ "RESET HAULED COUNTER (0)"
  end

  test "a traffic level is one press", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#traffic-quiet") |> render_click()

    assert OpsPanel.freighters() == OpsPanel.traffic_levels().quiet
    assert Dispatcher.fleet().freighters == OpsPanel.traffic_levels().quiet
    assert render(view) =~ "freighter_01"
  end

  test "a scenario is one press and sets every knob it names", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#scenario-cpu_bottleneck") |> render_click()

    assert OpsPanel.clerks() == 8
    assert Station.InspectionCrew.size() == 8
    assert OpsPanel.freighters() == 8
    assert OpsPanel.freighter_interval_ms() == 300
    # The screen caps the freighters like any ship; the setting is the ask.
    assert Dispatcher.fleet().freighters == Station.DockingBay.capacity()
    assert OpsPanel.current_scenario() == :cpu_bottleneck
    assert has_element?(view, "#scenario-cpu_bottleneck.bg-primary")
  end

  test "a scenario puts the knobs it does not name back to the baseline", %{conn: conn} do
    OpsPanel.set_hauler_interval(2_500)
    OpsPanel.set_haulers(5)
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#scenario-inspection_queue") |> render_click()

    assert OpsPanel.clerks() == 1
    assert OpsPanel.hauler_interval_ms() == Application.fetch_env!(:station, :hauler_interval_ms)
    assert OpsPanel.haulers() == Application.fetch_env!(:station, :haulers)
    assert Dispatcher.fleet().haulers == Application.fetch_env!(:station, :haulers)

    # Touch one knob and the preset is no longer the current one.
    view |> form("#hauler-pace-form", hauler_pace: %{ms: "2500"}) |> render_submit()
    assert OpsPanel.current_scenario() == nil
    refute has_element?(view, "#scenario-inspection_queue.bg-primary")
  end

  test "steady state is a scenario too, and undoes a bottleneck", %{conn: conn} do
    :ok = OpsPanel.apply_scenario(:cpu_bottleneck)
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#scenario-steady_state") |> render_click()

    assert OpsPanel.clerks() == 1
    assert OpsPanel.freighters() == 2
    assert OpsPanel.haulers() == 2
    assert Dispatcher.fleet() == %{haulers: 2, freighters: 2}
    assert OpsPanel.current_scenario() == :steady_state
  end

  test "an unknown scenario id is ignored", %{conn: conn} do
    before = OpsPanel.settings()
    {:ok, view, _html} = live(conn, ~p"/ops")

    render_click(view, "scenario", %{"id" => "nope"})

    assert OpsPanel.settings() == before
    assert OpsPanel.apply_scenario(:nope) == {:error, :unknown_scenario}
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
    settle()
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

  test "clerks are a button or a number, and one clerk is still a clerk", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> form("#clerks-form", clerks: %{count: "3"}) |> render_submit()
    assert Station.InspectionCrew.size() == 3
    assert OpsPanel.clerks() == 3

    # One clerk is a process of its own, not the warehouse doing the job.
    view |> element("#clerks-one") |> render_click()
    assert OpsPanel.clerks() == 1
    assert [:clerk_01] = Station.InspectionCrew.workers()

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
