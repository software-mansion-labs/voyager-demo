defmodule Station.CargoTest do
  use Station.Case, async: false

  alias Station.Cargo

  test "types read cheapest first, the way the registration screen tells it" do
    assert ["ice", "ore", "machinery", "antimatter"] = Cargo.types()
  end

  test "a hold is exactly as deep as configured" do
    hold = Cargo.build_hold("ore")
    assert length(hold) == Cargo.hold_size()
    assert Enum.all?(hold, &(&1.type == "ore"))
  end

  test "container size follows the preset" do
    assert Cargo.container_bytes("machinery") > Cargo.container_bytes("ore")
    assert Cargo.container_bytes("ore") > Cargo.container_bytes("ice")
  end

  # The whole "he is carrying ice, you are carrying antimatter" punchline rests
  # on this ordering. If a retune ever inverts it the demo stops making sense.
  test "inspection cost is ordered ice < ore < antimatter" do
    assert cost("ice") < cost("ore")
    assert cost("ore") < cost("antimatter")
  end

  # The crowd divides the cost, so a full room does not bury one clerk under
  # sixteen times the work - and the punchline ordering above survives it,
  # because every type is divided by the same room. Freighters are not the
  # room: their count is meant to be the load, so they leave the divisor alone.
  test "the crowd divides the inspection cost, and freighters do not" do
    solo = Cargo.effective_rounds("ore")

    {:ok, a} = Station.DockingBay.dock()
    {:ok, b} = Station.DockingBay.dock()

    assert Cargo.effective_rounds("ore") == div(solo, 2)

    :ok = Station.OpsPanel.set_traffic(1)
    assert Cargo.effective_rounds("ore") == div(solo, 2)

    Station.Ship.undock(a)
    Station.Ship.undock(b)
  end

  defp cost(type) do
    [container] = Cargo.build_hold(type, 1)
    {us, _} = :timer.tc(fn -> Enum.each(1..5, fn _ -> Cargo.inspect_container(container) end) end)
    us
  end
end
