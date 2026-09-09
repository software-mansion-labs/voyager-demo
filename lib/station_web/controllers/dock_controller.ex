defmodule StationWeb.DockController do
  @moduledoc """
  The way in and the way out. Neither has a form.

  Scanning the code lands on `/`, which docks a ship there and then - a name
  from the pool, a cargo type by lot - puts it in the session and sends the
  phone to the cockpit. The only thing between a visitor and the button is the
  redirect. A session whose ship parked itself in the hangar while the phone
  was dark gets that same ship back. Leaving undocks the ship for good and
  shows what it did, with one button back to a fresh one.
  """

  use StationWeb, :controller

  alias Station.DockingBay
  alias Station.Hangar
  alias Station.Leaderboard
  alias Station.ShipNames

  def new(conn, _params) do
    case current_ship(conn) do
      nil -> dock(conn, get_session(conn, :ship))
      _name -> redirect(conn, to: ~p"/ship")
    end
  end

  def delete(conn, _params) do
    slug = get_session(conn, :ship)
    ship = current_ship(conn)
    if ship, do: Station.Ship.undock(ship)
    # Leaving on purpose forgets the parked notes too: next scan is a fresh ship.
    Hangar.discard(slug)

    conn
    |> delete_session(:ship)
    |> assign(:page_title, "UNDOCKED · VOYAGER STATION")
    |> assign(:ship, ship || parked_name(slug))
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

  # A ship that was already waiting in the hangar still gets its farewell.
  defp parked_name(slug) when is_binary(slug) do
    if slug in ShipNames.pool(), do: ShipNames.to_process_name(slug), else: nil
  end

  defp parked_name(_), do: nil

  defp lookup(nil), do: nil

  defp lookup(slug) do
    name = String.to_existing_atom(ShipNames.prefix() <> slug)
    if Process.whereis(name), do: name, else: nil
  rescue
    ArgumentError -> nil
  end

  @doc "Whether this session's ship is waiting in the hangar for it to come back."
  @spec returning?(Plug.Conn.t() | map()) :: boolean()
  def returning?(%Plug.Conn{} = conn), do: conn |> get_session(:ship) |> Hangar.parked?()
  def returning?(%{"ship" => slug}), do: Hangar.parked?(slug)
  def returning?(_), do: false

  defp dock(conn, returning) do
    case DockingBay.dock(returning) do
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
