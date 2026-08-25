defmodule Station.LeaderboardTest do
  use Station.Case, async: false

  alias Station.Leaderboard

  test "counts containers per ship and keeps the newest cargo type" do
    Leaderboard.record("nostromo", "ice", 3)
    Leaderboard.record("nostromo", "ore", 2)
    Leaderboard.record("falcon", "antimatter", 1)

    assert %{containers: 5, cargo: "ore"} = Leaderboard.get("nostromo")
    assert Leaderboard.total_containers() == 6
    assert [%{ship: "nostromo"}, %{ship: "falcon"}] = Leaderboard.top(2)
  end

  # This is the third level of the persistence story the booth tells: the board
  # has to come back after the node itself is gone.
  test "survives a restart of the process that owns the table" do
    Leaderboard.record("nostromo", "ice", 7)
    :ok = Leaderboard.snapshot()

    pid = Process.whereis(Leaderboard)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}

    wait_for_restart()
    assert %{containers: 7} = Leaderboard.get("nostromo")
  end

  defp wait_for_restart(attempts \\ 100) do
    case Process.whereis(Leaderboard) do
      nil when attempts > 0 -> Process.sleep(10) && wait_for_restart(attempts - 1)
      pid when is_pid(pid) -> :ok
    end
  end
end
