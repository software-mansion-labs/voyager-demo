defmodule Station.CargoTest do
  use ExUnit.Case, async: true

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

  test "background cargo weights sum to one and exclude nothing" do
    weights = Cargo.weighted_types()
    assert_in_delta Enum.sum(Enum.map(weights, &elem(&1, 1))), 1.0, 0.0001
    assert Enum.map(weights, &elem(&1, 0)) |> Enum.sort() == Enum.sort(Cargo.types())
  end

  defp cost(type) do
    [container] = Cargo.build_hold(type, 1)
    {us, _} = :timer.tc(fn -> Enum.each(1..5, fn _ -> Cargo.inspect_container(container) end) end)
    us
  end
end
