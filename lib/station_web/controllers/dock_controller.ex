defmodule StationWeb.DockController do
  @moduledoc """
  The way in and the way out. Neither has a form.

  Scanning the code lands on `/`, which docks a ship there and then - a name
  from the pool, a cargo type by lot - puts it in the session and sends the
  phone to the cockpit. The only thing between a visitor and the button is the
  redirect. Leaving undocks the ship and shows what it did, with one button
  back to a fresh one.
  """

  use StationWeb, :controller

  alias Station.DockingBay
  alias Station.Leaderboard
  alias Station.ShipNames

  def new(conn, _params) do
    case current_ship(conn) do
      nil -> dock(conn)
      _name -> redirect(conn, to: ~p"/ship")
    end
  end

  def delete(conn, _params) do
    ship = current_ship(conn)
    if ship, do: Station.Ship.undock(ship)

    slug = ship && ShipNames.to_slug(ship)

    conn
    |> delete_session(:ship)
    |> assign(:page_title, "UNDOCKED · VOYAGER STATION")
    |> assign(:ship, ship)
    |> assign(:row, slug && Leaderboard.get(slug))
    |> assign(:rank, slug && Leaderboard.rank(slug))
    |> render(:farewell)
  end

  @doc """
  The ship named in this session, if it is still docked.

  Sessions carry the slug rather than the atom: a cookie signed before the last
  restart would otherwise ask the VM to resurrect an atom that no longer exists.
  """
  @spec current_ship(Plug.Conn.t() | map()) :: atom() | nil
  def current_ship(%Plug.Conn{} = conn), do: conn |> get_session(:ship) |> lookup()
  def current_ship(%{"ship" => slug}), do: lookup(slug)
  def current_ship(_), do: nil

  defp lookup(nil), do: nil

  defp lookup(slug) do
    name = String.to_existing_atom(ShipNames.prefix() <> slug)
    if Process.whereis(name), do: name, else: nil
  rescue
    ArgumentError -> nil
  end

  defp dock(conn) do
    case DockingBay.dock() do
      {:ok, registered} ->
        conn
        |> put_session(:ship, ShipNames.to_slug(registered))
        |> redirect(to: ~p"/ship")

      {:error, :at_capacity} ->
        conn
        |> put_flash(
          :info,
          "The station is full - #{DockingBay.capacity()} ships docked. You are in observer mode; try again in a minute."
        )
        |> redirect(to: ~p"/tv")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The docking bay refused that. Try again.")
        |> redirect(to: ~p"/tv")
    end
  end
end
