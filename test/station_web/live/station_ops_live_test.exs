defmodule StationWeb.StationOpsLiveTest do
  use StationWeb.ConnCase, async: false

  test "the television names every docked ship", %{conn: conn} do
    {:ok, first} = Station.DockingBay.dock()
    {:ok, second} = Station.DockingBay.dock()

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ to_string(first)
    assert html =~ to_string(second)
  end

  test "freighters are ships on the screen and in the DOCKED count", %{conn: conn} do
    {:ok, _} = Station.DockingBay.dock()
    :ok = Station.OpsPanel.set_traffic(2)

    {:ok, _view, html} = live(conn, ~p"/tv")

    assert html =~ "freighter_01"
    refute html =~ "freighters"
    assert %{"ships" => ships, "docked" => 3} = scene(html)
    assert length(ships) == 3
  end

  test "ops can take the QR codes off the television", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/tv")
    assert html =~ ~s(id="tv-qr")

    Station.OpsPanel.set_show_qr(false)
    send(view.pid, :refresh)
    refute render(view) =~ ~s(id="tv-qr")
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
    test "carries the hold tile by tile and the lanes the mode has", %{conn: conn} do
      [container] = Station.Cargo.build_hold("ice", 1)
      Station.Warehouse.accept(nil, container)
      :sys.get_state(Station.Warehouse)

      {:ok, view, html} = live(conn, ~p"/tv")

      assert %{"hold" => %{"ice" => 1, "ore" => 0}, "lanes" => 1, "mode" => "single_clerk"} =
               scene(html)

      Station.OpsPanel.set_warehouse_mode(:inspection_crew)
      send(view.pid, :refresh)

      assert %{"lanes" => lanes, "mode" => "inspection_crew"} = scene(render(view))
      assert lanes == Station.InspectionCrew.size()
    end

    test "berths are by arrival and stay put when the counts change", %{conn: conn} do
      {:ok, first} = Station.DockingBay.dock()
      {:ok, second} = Station.DockingBay.dock()
      :ok = Station.OpsPanel.set_traffic(1)

      {:ok, view, html} = live(conn, ~p"/tv")
      order = fn html -> for %{"id" => id} <- scene(html)["ships"], do: id end

      assert order.(html) == [to_string(first), to_string(second), "freighter_01"]

      # The second ship out-delivers the first; nobody moves.
      :ok = Station.Ship.transfer(second)
      :sys.get_state(Process.whereis(second))
      send(view.pid, :refresh)

      assert order.(render(view)) == [to_string(first), to_string(second), "freighter_01"]
    end

    test "opens with nothing in the air, then animates only real deliveries", %{conn: conn} do
      {:ok, name} = Station.DockingBay.dock()
      {:ok, view, html} = live(conn, ~p"/tv")

      # A screen that has been up for an hour must not open with an hour's worth
      # of cargo in flight, so the first snapshot carries no deltas at all.
      id = to_string(name)
      assert %{"ships" => [%{"delta" => 0, "id" => ^id}]} = scene(html)

      :ok = Station.Ship.transfer(name)
      :sys.get_state(Process.whereis(name))
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
end
