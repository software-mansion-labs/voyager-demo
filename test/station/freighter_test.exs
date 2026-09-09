defmodule Station.FreighterTest do
  use Station.Case, async: false

  alias Station.Dispatcher
  alias Station.FreighterLine
  alias Station.Metrics
  alias Station.OpsPanel

  test "traffic is off until ops turns it on" do
    dispatched()

    assert Dispatcher.fleet().freighters == 0
    assert FreighterLine.list() == []
  end

  test "ops staffs the line by level or by number, and the gauge follows" do
    :ok = OpsPanel.set_traffic(:quiet)
    dispatched()

    quiet = OpsPanel.traffic_levels().quiet
    assert Dispatcher.fleet().freighters == quiet
    assert :freighter_01 in FreighterLine.list()

    :ok = OpsPanel.set_traffic(1)
    dispatched()

    # The highest numbers go home first; the line keeps `_01` on the screen.
    assert [:freighter_01] == FreighterLine.list()

    assert {:error, :unknown_level} = OpsPanel.set_traffic(:hurricane)
  end

  test "with yield on, every visitor docking sends one freighter home" do
    :ok = OpsPanel.set_traffic(3)
    :ok = OpsPanel.set_yield_to_visitors(true)
    assert Dispatcher.fleet().freighters == 3

    {:ok, a} = Station.DockingBay.dock()
    {:ok, _b} = Station.DockingBay.dock()
    Dispatcher.reconcile()
    assert Dispatcher.fleet().freighters == 1
    assert FreighterLine.list() == [:freighter_01]

    # The screen holds the same crowd: two people, one robot.
    Station.Ship.undock(a)
    Dispatcher.reconcile()
    assert Dispatcher.fleet().freighters == 2

    # Yield off: freighters hold what berths the visitors leave, never more.
    :ok = OpsPanel.set_yield_to_visitors(false)
    assert Dispatcher.fleet().freighters == Station.DockingBay.capacity() - 1
  end

  test "a freighter ships to the warehouse but never to the leaderboard" do
    :ok = OpsPanel.set_traffic(1)
    dispatched()

    [name] = FreighterLine.list()
    pid = Process.whereis(name)

    send(pid, :tick)
    :sys.get_state(pid)
    settle()

    assert %{delivered: 1, freighter?: true} = Station.Freighter.status(name)
    assert Metrics.get(:accepted) == 1
    assert Station.Leaderboard.size() == 0
  end

  test "an empty hold refills on its own" do
    :ok = OpsPanel.set_traffic(1)
    dispatched()

    [name] = FreighterLine.list()
    pid = Process.whereis(name)

    for _ <- 1..Station.Cargo.hold_size(), do: send(pid, :tick)
    :sys.get_state(pid)
    settle()
    assert %{hold: 0} = Station.Freighter.status(name)

    send(pid, :tick)
    :sys.get_state(pid)
    assert %{hold: hold, refills: 1} = Station.Freighter.status(name)
    assert hold == Station.Cargo.hold_size()
  end
end
