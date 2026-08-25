defmodule Station.ShipNamesTest do
  use ExUnit.Case, async: true

  alias Station.ShipNames

  describe "normalize/1" do
    test "slugifies whatever a visitor typed" do
      assert {:ok, "millennium_falcon"} = ShipNames.normalize("Millennium Falcon!!")
      assert {:ok, "nostromo"} = ShipNames.normalize("  Nostromo  ")
      assert {:ok, "zolw_2000"} = ShipNames.normalize("Żółw 2000")
    end

    test "caps the length so one visitor cannot mint a huge atom" do
      {:ok, slug} = ShipNames.normalize(String.duplicate("a", 500))
      assert String.length(slug) == ShipNames.max_length()
    end

    test "rejects what should never reach the big screen" do
      assert {:error, :too_short} = ShipNames.normalize("!")
      assert {:error, :too_short} = ShipNames.normalize("")
      assert {:error, :blocked} = ShipNames.normalize("kurwa mac")
      assert {:error, :blocked} = ShipNames.normalize("f u c k")
      assert {:error, :invalid} = ShipNames.normalize(:not_a_string)
    end
  end

  test "the generated fallback pool is finite" do
    names = for seq <- 0..5_000, into: MapSet.new(), do: ShipNames.generated(seq)
    assert MapSet.size(names) == 500
  end

  test "round trips through the registered name" do
    assert "nostromo" == "nostromo" |> ShipNames.to_process_name() |> ShipNames.to_slug()
  end
end
