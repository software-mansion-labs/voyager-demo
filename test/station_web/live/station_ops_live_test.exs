defmodule StationWeb.StationOpsLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Cargo
  alias Station.Events
  alias Station.Warehouse

  test "the television names every docked ship", %{conn: conn} do
    {:ok, _} = Station.DockingBay.dock("Nostromo", "ore")
    {:ok, _} = Station.DockingBay.dock("Rocinante", "ice")

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "ship_nostromo"
    assert html =~ "ship_rocinante"
    assert html =~ "station_leaderboard"
  end

  test "the board only counts visitors, never the background fleet", %{conn: conn} do
    [container] = Cargo.build_hold("ore", 1)

    Warehouse.accept("nostromo", container)
    Warehouse.accept(nil, container)
    :sys.get_state(Warehouse)

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "nostromo"
    assert Station.Leaderboard.size() == 1
  end

  test "the television carries the way in, as a code and as a line to type", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "SCAN TO"

    # The line under the code is wherever the station can actually be reached,
    # minus the scheme nobody types and every phone adds back on its own.
    url = Station.Booth.dock_url()
    assert html =~ String.replace_prefix(url, "http://", "")
    refute html =~ url
  end

  describe "the scene payload" do
    test "opens with nothing in the air, then animates only real deliveries", %{conn: conn} do
      {:ok, name} = Station.DockingBay.dock("Nostromo", "ore")
      {:ok, view, html} = live(conn, ~p"/tv")

      # A screen that has been up for an hour must not open with an hour's worth
      # of cargo in flight, so the first snapshot carries no deltas at all.
      assert %{"ships" => [%{"delta" => 0, "cargo" => "ore", "id" => "ship_nostromo"}]} =
               scene(html)

      {:ok, _} = Station.Ship.transfer(name)
      send(view.pid, :refresh)

      assert %{"ships" => [%{"delta" => 1}]} = scene(render(view))
    end
  end

  defp scene(html) do
    [payload] = Regex.run(~r/data-scene="([^"]*)"/, html, capture: :all_but_first)

    payload
    |> String.replace("&quot;", ~s("))
    |> String.replace("&amp;", "&")
    |> Jason.decode!()
  end

  test "the log collapses a line that repeats instead of scrolling it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tv")

    for _ <- 1..3, do: Events.emit(:test, "WAREHOUSE OVER CAPACITY", :warning)
    # The LiveView has to process all three broadcasts before we look.
    _ = :sys.get_state(view.pid)

    assert render(view) =~ "x3"
  end
end
