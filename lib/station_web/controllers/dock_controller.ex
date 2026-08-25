defmodule StationWeb.DockController do
  @moduledoc """
  Registration: two fields, and then the visitor is a process in the tree.

  A plain controller rather than a LiveView, because the whole job is to
  validate two strings, start a GenServer and put a name in the session. The
  live part of the visitor's evening starts on the next page.
  """

  use StationWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Station.Cargo
  alias Station.DockingBay
  alias Station.ShipNames

  def new(conn, _params) do
    case current_ship(conn) do
      nil -> render_form(conn, %{}, nil)
      _name -> redirect(conn, to: ~p"/ship")
    end
  end

  def create(conn, %{"ship" => %{"name" => name, "cargo" => cargo}}) do
    case DockingBay.dock(name, cargo) do
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

      {:error, reason} ->
        render_form(conn, %{"name" => name, "cargo" => cargo}, error_message(reason))
    end
  end

  def create(conn, _params), do: render_form(conn, %{}, "Pick a name and a cargo type.")

  def delete(conn, _params) do
    case current_ship(conn) do
      nil -> :ok
      name -> Station.Ship.undock(name)
    end

    conn
    |> delete_session(:ship)
    |> redirect(to: ~p"/")
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

  defp render_form(conn, params, error) do
    conn
    |> assign(:page_title, "REGISTER YOUR SHIP · STATION VOY-1")
    |> assign(:form, to_form(params, as: :ship))
    |> assign(:error, error)
    |> assign(:cargo_types, cargo_options())
    |> assign(:docked, DockingBay.count())
    |> assign(:capacity, DockingBay.capacity())
    |> assign(:atoms, DockingBay.atom_budget())
    |> render(:new)
  end

  defp cargo_options do
    for type <- Cargo.types() do
      preset = Cargo.preset(type)

      %{
        value: type,
        label: preset.label,
        blurb: preset.blurb,
        bytes: Cargo.container_bytes(type),
        rounds: preset.inspection_rounds
      }
    end
  end

  defp error_message(:too_short), do: "That name is too short. Two letters or more, please."
  defp error_message(:blocked), do: "Pick another name. That one is not going on the big screen."
  defp error_message(:name_taken), do: "A ship is already docked under that name. Try another."
  defp error_message(:invalid), do: "Pick a cargo type."
  defp error_message(_), do: "The docking bay refused that. Try again."
end
