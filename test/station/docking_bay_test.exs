defmodule Station.DockingBayTest do
  use Station.Case, async: false

  alias Station.DockingBay
  alias Station.Ship
  alias Station.ShipNames

  test "docking needs nothing from the visitor and registers a named process" do
    assert {:ok, name} = DockingBay.dock()

    assert is_pid(Process.whereis(name))
    assert name in DockingBay.list()
    assert ShipNames.to_slug(name) in ShipNames.pool()
    assert %{cargo_type: cargo} = Ship.status(name)
    assert cargo in Station.Cargo.types()
  end

  test "two ships never share a name" do
    {:ok, first} = DockingBay.dock()
    {:ok, second} = DockingBay.dock()

    assert first != second
  end

  test "the cap is enforced, and it is a cap on the eye not the runtime" do
    capacity = DockingBay.capacity()

    for _ <- 1..capacity, do: assert({:ok, _} = DockingBay.dock())

    assert DockingBay.full?()
    assert {:error, :at_capacity} = DockingBay.dock()
  end

  test "freighters take berths like anyone else, and yield them to a person" do
    capacity = DockingBay.capacity()
    :ok = Station.OpsPanel.set_traffic(capacity)
    assert DockingBay.full?()

    # Yield off: a full station is full.
    assert {:error, :at_capacity} = DockingBay.dock()

    # Yield on: one freighter goes home this instant and the visitor docks.
    :ok = Station.OpsPanel.set_yield_to_visitors(true)
    assert {:ok, name} = DockingBay.dock()
    assert is_pid(Process.whereis(name))
    assert Station.FreighterLine.count() == capacity - 1
    assert DockingBay.occupied() == capacity

    # The dispatcher agrees on its next pass, so nobody comes back.
    Station.Dispatcher.reconcile()
    assert Station.FreighterLine.count() == capacity - 1
  end

  test "ops can remove a ship that should not be on the screen" do
    {:ok, name} = DockingBay.dock()
    ref = Process.monitor(Process.whereis(name))

    DockingBay.remove(name)

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert DockingBay.list() == []
  end

  test "undocking leaves nothing behind but the leaderboard row" do
    {:ok, name} = DockingBay.dock()
    :ok = Ship.transfer(name)
    :sys.get_state(Process.whereis(name))
    settle()

    ref = Process.monitor(Process.whereis(name))
    Ship.undock(name)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert Process.whereis(name) == nil
    assert %{containers: 1} = Station.Leaderboard.get(ShipNames.to_slug(name))
  end
end
