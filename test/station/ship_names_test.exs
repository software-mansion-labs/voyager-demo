defmodule Station.ShipNamesTest do
  use ExUnit.Case, async: true

  alias Station.ShipNames

  test "the pool is finite, and that is the whole atom story" do
    pool = ShipNames.pool()

    assert length(pool) == ShipNames.pool_size()
    assert length(pool) == length(Enum.uniq(pool))
    assert Enum.all?(pool, &(&1 =~ ~r/^[a-z]+_[a-z]+$/))
  end

  test "picks a name that nobody has" do
    taken = ShipNames.pool() |> Enum.take(5) |> Enum.map(&ShipNames.to_process_name/1)

    for _ <- 1..50 do
      assert {:ok, slug} = ShipNames.pick(taken)
      refute ShipNames.to_process_name(slug) in taken
      assert slug in ShipNames.pool()
    end
  end

  test "an exhausted pool says so instead of inventing an atom" do
    assert :error = ShipNames.pick(ShipNames.pool())
  end

  test "only a slug from the pool ever becomes an atom" do
    assert_raise FunctionClauseError, fn ->
      ShipNames.to_process_name("anything_a_visitor_typed")
    end
  end

  test "round trips through the registered name" do
    [slug | _] = ShipNames.pool()
    assert slug == slug |> ShipNames.to_process_name() |> ShipNames.to_slug()
  end
end
