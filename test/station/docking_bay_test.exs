defmodule Station.DockingBayTest do
  use Station.Case, async: false

  alias Station.DockingBay
  alias Station.Ship

  test "docking registers the ship under the name the visitor will hunt for" do
    assert {:ok, :ship_nostromo} = DockingBay.dock("Nostromo", "ice")
    assert is_pid(Process.whereis(:ship_nostromo))
    assert :ship_nostromo in DockingBay.list()
  end

  test "the same name cannot dock twice" do
    {:ok, _} = DockingBay.dock("Nostromo", "ice")
    assert {:error, :name_taken} = DockingBay.dock("nostromo", "ore")
  end

  test "rejects a bad name or a cargo that does not exist" do
    assert {:error, :blocked} = DockingBay.dock("kurwa", "ore")
    assert {:error, :too_short} = DockingBay.dock("x", "ore")
    assert {:error, :invalid} = DockingBay.dock("Nostromo", "plutonium")
  end

  test "the cap is enforced, and it is a cap on the eye not the runtime" do
    capacity = DockingBay.capacity()

    for n <- 1..capacity do
      assert {:ok, _} = DockingBay.dock("ship number #{n}", "ice")
    end

    assert DockingBay.full?()
    assert {:error, :at_capacity} = DockingBay.dock("one too many", "ice")
  end

  test "ops can remove a ship that should not be on the screen" do
    {:ok, name} = DockingBay.dock("Nostromo", "ice")
    ref = Process.monitor(Process.whereis(name))

    DockingBay.remove(name)

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert DockingBay.list() == []
  end

  test "undocking leaves nothing behind but the leaderboard row" do
    {:ok, name} = DockingBay.dock("Nostromo", "ice")
    {:ok, _} = Ship.transfer(name)
    settle()

    ref = Process.monitor(Process.whereis(name))
    Ship.undock(name)
    assert_receive {:DOWN, ^ref, :process, _, _}

    assert Process.whereis(name) == nil
    assert %{containers: 1} = Station.Leaderboard.get("nostromo")
  end

  test "reports how much of the atom budget the booth has burned" do
    assert %{used: used, budget: budget} = DockingBay.atom_budget()
    assert used >= 0
    assert budget > 0
  end
end
