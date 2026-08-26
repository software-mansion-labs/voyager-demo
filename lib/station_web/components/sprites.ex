defmodule StationWeb.Sprites do
  @moduledoc """
  The station drawn as pixels.

  Every sprite lives on a 16 or 32 unit grid, one rect per horizontal run, with
  `shape-rendering: crispEdges` and no curve anywhere. Colour comes from
  `currentColor`, so a sprite takes the meaning of wherever it is placed: ships
  cyan, warehouse amber, antimatter magenta.

  The shapes are defined once, in `defs/1` at the top of the page, and every
  sprite on the page is a two node `<use>` of one of them. Drawing them inline
  instead cost the television five thousand DOM nodes and a visibly slower
  screen, which is a strange way to spend the budget on a demo about not
  overloading one process.
  """

  use Phoenix.Component

  @doc "Cargo colour token for a cargo type, so one cargo means one colour everywhere."
  @spec cargo_color(String.t()) :: String.t()
  def cargo_color("ice"), do: "text-info"
  def cargo_color("ore"), do: "text-primary"
  def cargo_color("machinery"), do: "text-warning"
  def cargo_color("antimatter"), do: "text-accent"
  def cargo_color(_), do: "text-base-content"

  @doc """
  The sprite sheet. Render once per page, before anything that uses a sprite.
  """
  def defs(assigns) do
    ~H"""
    <svg width="0" height="0" aria-hidden="true" class="absolute">
      <defs>
        <symbol id="sprite-container" viewBox="0 0 16 16">
          <rect x="2" y="2" width="12" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="3" width="10" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="4" width="1" height="1" fill="currentColor" />
          <rect x="5" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="4" width="1" height="1" fill="currentColor" />
          <rect x="7" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="4" width="1" height="1" fill="currentColor" />
          <rect x="9" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="4" width="1" height="1" fill="currentColor" />
          <rect x="11" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="4" width="1" height="1" fill="currentColor" />
          <rect x="13" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="5" width="1" height="1" fill="currentColor" />
          <rect x="5" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="5" width="1" height="1" fill="currentColor" />
          <rect x="7" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="5" width="1" height="1" fill="currentColor" />
          <rect x="9" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="5" width="1" height="1" fill="currentColor" />
          <rect x="11" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="5" width="1" height="1" fill="currentColor" />
          <rect x="13" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="6" width="1" height="1" fill="currentColor" />
          <rect x="5" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="6" width="1" height="1" fill="currentColor" />
          <rect x="7" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="6" width="1" height="1" fill="currentColor" />
          <rect x="9" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="6" width="1" height="1" fill="currentColor" />
          <rect x="11" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="6" width="1" height="1" fill="currentColor" />
          <rect x="13" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="7" width="12" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="8" width="1" height="1" fill="currentColor" />
          <rect x="5" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="8" width="1" height="1" fill="currentColor" />
          <rect x="7" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="8" width="1" height="1" fill="currentColor" />
          <rect x="9" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="8" width="1" height="1" fill="currentColor" />
          <rect x="11" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="8" width="1" height="1" fill="currentColor" />
          <rect x="13" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="9" width="1" height="1" fill="currentColor" />
          <rect x="5" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="9" width="1" height="1" fill="currentColor" />
          <rect x="7" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="9" width="1" height="1" fill="currentColor" />
          <rect x="9" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="9" width="1" height="1" fill="currentColor" />
          <rect x="11" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="9" width="1" height="1" fill="currentColor" />
          <rect x="13" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="10" width="1" height="1" fill="currentColor" />
          <rect x="5" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="10" width="1" height="1" fill="currentColor" />
          <rect x="7" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="8" y="10" width="1" height="1" fill="currentColor" />
          <rect x="9" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="10" y="10" width="1" height="1" fill="currentColor" />
          <rect x="11" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="10" width="1" height="1" fill="currentColor" />
          <rect x="13" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="11" width="10" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="12" width="12" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="14" y="13" width="1" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-ship" viewBox="0 0 16 16">
          <rect x="10" y="2" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="9" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="3" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="11" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="4" width="4" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="4" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="4" width="1" height="1" fill="currentColor" />
          <rect x="13" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="5" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="5" width="7" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="5" width="1" height="1" fill="currentColor" />
          <rect x="14" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="6" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="5" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="6" width="9" height="1" fill="currentColor" />
          <rect x="15" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="7" width="10" height="1" fill="currentColor" />
          <rect x="14" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="4" y="8" width="10" height="1" fill="currentColor" />
          <rect x="14" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="9" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="5" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="9" width="8" height="1" fill="currentColor" />
          <rect x="14" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="5" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="10" width="7" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="10" width="1" height="1" fill="currentColor" />
          <rect x="14" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="11" width="4" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="11" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="11" width="1" height="1" fill="currentColor" />
          <rect x="13" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="9" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="12" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="11" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="13" width="1" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-hauler" viewBox="0 0 16 16">
          <rect x="2" y="2" width="4" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="3" width="4" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="4" width="2" height="1" fill="currentColor" />
          <rect x="5" y="4" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="7" y="4" width="5" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="5" width="8" height="1" fill="currentColor" />
          <rect x="11" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="6" width="10" height="1" fill="currentColor" />
          <rect x="13" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="7" width="10" height="1" fill="currentColor" />
          <rect x="13" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="8" width="8" height="1" fill="currentColor" />
          <rect x="11" y="8" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="13" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="9" width="4" height="1" fill="var(--sprite-lit)" />
          <rect x="6" y="9" width="7" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="10" width="4" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-crate_small" viewBox="0 0 16 16">
          <rect x="1" y="1" width="14" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="2" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="2" width="12" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="2" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="3" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="3" width="10" height="1" fill="currentColor" />
          <rect x="13" y="3" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="4" width="10" height="1" fill="currentColor" />
          <rect x="13" y="4" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="5" width="14" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="6" width="10" height="1" fill="currentColor" />
          <rect x="13" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="7" width="10" height="1" fill="currentColor" />
          <rect x="13" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="8" width="10" height="1" fill="currentColor" />
          <rect x="13" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="9" width="14" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="10" width="10" height="1" fill="currentColor" />
          <rect x="13" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="11" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="3" y="11" width="10" height="1" fill="currentColor" />
          <rect x="13" y="11" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="12" width="12" height="1" fill="var(--sprite-lit)" />
          <rect x="14" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="13" width="14" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-warehouse" viewBox="0 0 32 32">
          <rect x="14" y="2" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="2" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="14" y="3" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="16" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="3" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="12" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="4" width="4" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="4" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="12" y="5" width="6" height="1" fill="var(--sprite-lit)" />
          <rect x="18" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="6" width="8" height="1" fill="var(--sprite-lit)" />
          <rect x="19" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="9" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="7" width="10" height="1" fill="var(--sprite-lit)" />
          <rect x="20" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="9" y="8" width="12" height="1" fill="var(--sprite-lit)" />
          <rect x="21" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="9" width="14" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="10" width="18" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="11" width="16" height="1" fill="currentColor" />
          <rect x="23" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="12" width="1" height="1" fill="currentColor" />
          <rect x="8" y="12" width="14" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="12" width="1" height="1" fill="currentColor" />
          <rect x="23" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="13" width="1" height="1" fill="currentColor" />
          <rect x="8" y="13" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="13" width="11" height="1" fill="currentColor" />
          <rect x="20" y="13" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="13" width="1" height="1" fill="currentColor" />
          <rect x="23" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="14" width="1" height="1" fill="currentColor" />
          <rect x="8" y="14" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="14" width="1" height="1" fill="currentColor" />
          <rect x="10" y="14" width="9" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="14" width="1" height="1" fill="currentColor" />
          <rect x="20" y="14" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="14" width="1" height="1" fill="currentColor" />
          <rect x="23" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="15" width="1" height="1" fill="currentColor" />
          <rect x="8" y="15" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="15" width="1" height="1" fill="currentColor" />
          <rect x="10" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="15" width="6" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="15" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="15" width="1" height="1" fill="currentColor" />
          <rect x="20" y="15" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="15" width="1" height="1" fill="currentColor" />
          <rect x="23" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="16" width="1" height="1" fill="currentColor" />
          <rect x="8" y="16" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="16" width="1" height="1" fill="currentColor" />
          <rect x="10" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="16" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="16" width="4" height="1" fill="currentColor" />
          <rect x="16" y="16" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="16" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="16" width="1" height="1" fill="currentColor" />
          <rect x="20" y="16" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="16" width="1" height="1" fill="currentColor" />
          <rect x="23" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="17" width="1" height="1" fill="currentColor" />
          <rect x="8" y="17" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="17" width="1" height="1" fill="currentColor" />
          <rect x="10" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="17" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="17" width="4" height="1" fill="currentColor" />
          <rect x="16" y="17" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="17" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="17" width="1" height="1" fill="currentColor" />
          <rect x="20" y="17" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="17" width="1" height="1" fill="currentColor" />
          <rect x="23" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="18" width="1" height="1" fill="currentColor" />
          <rect x="8" y="18" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="18" width="1" height="1" fill="currentColor" />
          <rect x="10" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="18" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="18" width="4" height="1" fill="currentColor" />
          <rect x="16" y="18" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="18" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="18" width="1" height="1" fill="currentColor" />
          <rect x="20" y="18" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="18" width="1" height="1" fill="currentColor" />
          <rect x="23" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="19" width="1" height="1" fill="currentColor" />
          <rect x="8" y="19" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="19" width="1" height="1" fill="currentColor" />
          <rect x="10" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="19" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="19" width="4" height="1" fill="currentColor" />
          <rect x="16" y="19" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="19" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="19" width="1" height="1" fill="currentColor" />
          <rect x="20" y="19" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="19" width="1" height="1" fill="currentColor" />
          <rect x="23" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="20" width="1" height="1" fill="currentColor" />
          <rect x="8" y="20" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="20" width="1" height="1" fill="currentColor" />
          <rect x="10" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="20" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="20" width="4" height="1" fill="currentColor" />
          <rect x="16" y="20" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="17" y="20" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="20" width="1" height="1" fill="currentColor" />
          <rect x="20" y="20" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="20" width="1" height="1" fill="currentColor" />
          <rect x="23" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="21" width="1" height="1" fill="currentColor" />
          <rect x="8" y="21" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="21" width="1" height="1" fill="currentColor" />
          <rect x="10" y="21" width="9" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="21" width="1" height="1" fill="currentColor" />
          <rect x="20" y="21" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="21" width="1" height="1" fill="currentColor" />
          <rect x="23" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="22" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="22" width="1" height="1" fill="currentColor" />
          <rect x="8" y="22" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="9" y="22" width="11" height="1" fill="currentColor" />
          <rect x="20" y="22" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="22" y="22" width="1" height="1" fill="currentColor" />
          <rect x="23" y="22" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="22" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="23" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="23" width="16" height="1" fill="currentColor" />
          <rect x="23" y="23" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="23" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="24" width="18" height="1" fill="var(--sprite-ink)" />
          <rect x="30" y="24" width="1" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-dock" viewBox="0 0 32 32">
          <rect x="3" y="4" width="23" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="5" width="21" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="6" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="5" y="6" width="18" height="1" fill="currentColor" />
          <rect x="23" y="6" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="7" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="5" y="7" width="1" height="1" fill="currentColor" />
          <rect x="6" y="7" width="16" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="7" width="1" height="1" fill="currentColor" />
          <rect x="23" y="7" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="8" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="5" y="8" width="1" height="1" fill="currentColor" />
          <rect x="6" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="8" width="14" height="1" fill="var(--sprite-lit)" />
          <rect x="21" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="8" width="1" height="1" fill="currentColor" />
          <rect x="23" y="8" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="8" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="9" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="5" y="9" width="1" height="1" fill="currentColor" />
          <rect x="6" y="9" width="16" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="9" width="1" height="1" fill="currentColor" />
          <rect x="23" y="9" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="9" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="10" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="5" y="10" width="18" height="1" fill="currentColor" />
          <rect x="23" y="10" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="10" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="4" y="11" width="21" height="1" fill="var(--sprite-lit)" />
          <rect x="25" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="3" y="12" width="23" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="15" width="1" height="1" fill="var(--sprite-ink)" />
        </symbol>
        <symbol id="sprite-station_hub" viewBox="0 0 64 32">
          <rect x="31" y="0" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="31" y="1" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="31" y="2" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="3" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="4" width="44" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="18" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="21" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="24" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="27" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="30" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="33" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="36" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="39" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="42" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="45" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="48" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="5" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="51" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="5" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="53" y="5" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="6" width="1" height="1" fill="currentColor" />
          <rect x="12" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="6" width="2" height="1" fill="currentColor" />
          <rect x="15" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="6" width="2" height="1" fill="currentColor" />
          <rect x="18" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="6" width="2" height="1" fill="currentColor" />
          <rect x="21" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="6" width="2" height="1" fill="currentColor" />
          <rect x="24" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="6" width="2" height="1" fill="currentColor" />
          <rect x="27" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="6" width="2" height="1" fill="currentColor" />
          <rect x="30" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="6" width="2" height="1" fill="currentColor" />
          <rect x="33" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="6" width="2" height="1" fill="currentColor" />
          <rect x="36" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="6" width="2" height="1" fill="currentColor" />
          <rect x="39" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="6" width="2" height="1" fill="currentColor" />
          <rect x="42" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="6" width="2" height="1" fill="currentColor" />
          <rect x="45" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="6" width="2" height="1" fill="currentColor" />
          <rect x="48" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="6" width="2" height="1" fill="currentColor" />
          <rect x="51" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="6" width="1" height="1" fill="currentColor" />
          <rect x="53" y="6" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="7" width="1" height="1" fill="currentColor" />
          <rect x="12" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="7" width="2" height="1" fill="currentColor" />
          <rect x="15" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="7" width="2" height="1" fill="currentColor" />
          <rect x="18" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="7" width="2" height="1" fill="currentColor" />
          <rect x="21" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="7" width="2" height="1" fill="currentColor" />
          <rect x="24" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="7" width="2" height="1" fill="currentColor" />
          <rect x="27" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="7" width="2" height="1" fill="currentColor" />
          <rect x="30" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="7" width="2" height="1" fill="currentColor" />
          <rect x="33" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="7" width="2" height="1" fill="currentColor" />
          <rect x="36" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="7" width="2" height="1" fill="currentColor" />
          <rect x="39" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="7" width="2" height="1" fill="currentColor" />
          <rect x="42" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="7" width="2" height="1" fill="currentColor" />
          <rect x="45" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="7" width="2" height="1" fill="currentColor" />
          <rect x="48" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="7" width="2" height="1" fill="currentColor" />
          <rect x="51" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="7" width="1" height="1" fill="currentColor" />
          <rect x="53" y="7" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="8" width="44" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="9" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="10" width="52" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="11" width="50" height="1" fill="var(--sprite-lit)" />
          <rect x="57" y="11" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="12" width="12" height="1" fill="currentColor" />
          <rect x="19" y="12" width="26" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="12" width="12" height="1" fill="currentColor" />
          <rect x="57" y="12" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="13" width="12" height="1" fill="currentColor" />
          <rect x="19" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="13" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="13" width="12" height="1" fill="currentColor" />
          <rect x="57" y="13" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="14" width="7" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="14" width="2" height="1" fill="currentColor" />
          <rect x="10" y="14" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="14" width="1" height="1" fill="currentColor" />
          <rect x="13" y="14" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="14" width="4" height="1" fill="currentColor" />
          <rect x="19" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="14" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="14" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="14" width="5" height="1" fill="currentColor" />
          <rect x="50" y="14" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="52" y="14" width="1" height="1" fill="currentColor" />
          <rect x="53" y="14" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="55" y="14" width="1" height="1" fill="currentColor" />
          <rect x="56" y="14" width="7" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="15" width="5" height="1" fill="var(--sprite-lit)" />
          <rect x="7" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="15" width="2" height="1" fill="currentColor" />
          <rect x="10" y="15" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="15" width="1" height="1" fill="currentColor" />
          <rect x="13" y="15" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="15" width="4" height="1" fill="currentColor" />
          <rect x="19" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="15" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="15" width="5" height="1" fill="currentColor" />
          <rect x="50" y="15" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="52" y="15" width="1" height="1" fill="currentColor" />
          <rect x="53" y="15" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="55" y="15" width="1" height="1" fill="currentColor" />
          <rect x="56" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="57" y="15" width="5" height="1" fill="var(--sprite-lit)" />
          <rect x="62" y="15" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="0" y="16" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="16" width="5" height="1" fill="currentColor" />
          <rect x="7" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="16" width="11" height="1" fill="currentColor" />
          <rect x="19" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="16" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="16" width="11" height="1" fill="currentColor" />
          <rect x="56" y="16" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="57" y="16" width="5" height="1" fill="currentColor" />
          <rect x="62" y="16" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="0" y="17" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="17" width="5" height="1" fill="currentColor" />
          <rect x="7" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="17" width="11" height="1" fill="currentColor" />
          <rect x="19" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="17" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="17" width="11" height="1" fill="currentColor" />
          <rect x="56" y="17" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="57" y="17" width="5" height="1" fill="currentColor" />
          <rect x="62" y="17" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="0" y="18" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="18" width="5" height="1" fill="currentColor" />
          <rect x="7" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="18" width="11" height="1" fill="currentColor" />
          <rect x="19" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="18" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="18" width="11" height="1" fill="currentColor" />
          <rect x="56" y="18" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="57" y="18" width="5" height="1" fill="currentColor" />
          <rect x="62" y="18" width="2" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="2" y="19" width="5" height="1" fill="currentColor" />
          <rect x="7" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="19" width="2" height="1" fill="currentColor" />
          <rect x="10" y="19" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="19" width="1" height="1" fill="currentColor" />
          <rect x="13" y="19" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="19" width="4" height="1" fill="currentColor" />
          <rect x="19" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="19" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="19" width="5" height="1" fill="currentColor" />
          <rect x="50" y="19" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="52" y="19" width="1" height="1" fill="currentColor" />
          <rect x="53" y="19" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="55" y="19" width="1" height="1" fill="currentColor" />
          <rect x="56" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="57" y="19" width="5" height="1" fill="currentColor" />
          <rect x="62" y="19" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="1" y="20" width="7" height="1" fill="var(--sprite-ink)" />
          <rect x="8" y="20" width="2" height="1" fill="currentColor" />
          <rect x="10" y="20" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="20" width="1" height="1" fill="currentColor" />
          <rect x="13" y="20" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="20" width="4" height="1" fill="currentColor" />
          <rect x="19" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="20" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="20" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="20" width="5" height="1" fill="currentColor" />
          <rect x="50" y="20" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="52" y="20" width="1" height="1" fill="currentColor" />
          <rect x="53" y="20" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="55" y="20" width="1" height="1" fill="currentColor" />
          <rect x="56" y="20" width="7" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="21" width="12" height="1" fill="currentColor" />
          <rect x="19" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="20" y="21" width="24" height="1" fill="var(--sprite-bay)" />
          <rect x="44" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="21" width="12" height="1" fill="currentColor" />
          <rect x="57" y="21" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="22" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="22" width="12" height="1" fill="currentColor" />
          <rect x="19" y="22" width="26" height="1" fill="var(--sprite-ink)" />
          <rect x="45" y="22" width="12" height="1" fill="currentColor" />
          <rect x="57" y="22" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="23" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="7" y="23" width="50" height="1" fill="currentColor" />
          <rect x="57" y="23" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="6" y="24" width="52" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="25" width="44" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="26" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="12" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="15" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="18" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="21" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="24" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="27" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="30" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="33" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="36" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="39" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="42" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="45" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="48" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="26" width="2" height="1" fill="var(--sprite-lit)" />
          <rect x="51" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="26" width="1" height="1" fill="var(--sprite-lit)" />
          <rect x="53" y="26" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="27" width="1" height="1" fill="currentColor" />
          <rect x="12" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="27" width="2" height="1" fill="currentColor" />
          <rect x="15" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="27" width="2" height="1" fill="currentColor" />
          <rect x="18" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="27" width="2" height="1" fill="currentColor" />
          <rect x="21" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="27" width="2" height="1" fill="currentColor" />
          <rect x="24" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="27" width="2" height="1" fill="currentColor" />
          <rect x="27" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="27" width="2" height="1" fill="currentColor" />
          <rect x="30" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="27" width="2" height="1" fill="currentColor" />
          <rect x="33" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="27" width="2" height="1" fill="currentColor" />
          <rect x="36" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="27" width="2" height="1" fill="currentColor" />
          <rect x="39" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="27" width="2" height="1" fill="currentColor" />
          <rect x="42" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="27" width="2" height="1" fill="currentColor" />
          <rect x="45" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="27" width="2" height="1" fill="currentColor" />
          <rect x="48" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="27" width="2" height="1" fill="currentColor" />
          <rect x="51" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="27" width="1" height="1" fill="currentColor" />
          <rect x="53" y="27" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="11" y="28" width="1" height="1" fill="currentColor" />
          <rect x="12" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="13" y="28" width="2" height="1" fill="currentColor" />
          <rect x="15" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="16" y="28" width="2" height="1" fill="currentColor" />
          <rect x="18" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="19" y="28" width="2" height="1" fill="currentColor" />
          <rect x="21" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="22" y="28" width="2" height="1" fill="currentColor" />
          <rect x="24" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="25" y="28" width="2" height="1" fill="currentColor" />
          <rect x="27" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="28" y="28" width="2" height="1" fill="currentColor" />
          <rect x="30" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="31" y="28" width="2" height="1" fill="currentColor" />
          <rect x="33" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="34" y="28" width="2" height="1" fill="currentColor" />
          <rect x="36" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="37" y="28" width="2" height="1" fill="currentColor" />
          <rect x="39" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="40" y="28" width="2" height="1" fill="currentColor" />
          <rect x="42" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="43" y="28" width="2" height="1" fill="currentColor" />
          <rect x="45" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="46" y="28" width="2" height="1" fill="currentColor" />
          <rect x="48" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="49" y="28" width="2" height="1" fill="currentColor" />
          <rect x="51" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="52" y="28" width="1" height="1" fill="currentColor" />
          <rect x="53" y="28" width="1" height="1" fill="var(--sprite-ink)" />
          <rect x="10" y="29" width="44" height="1" fill="var(--sprite-ink)" />
        </symbol>
      </defs>
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def container(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-container" />
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def ship(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-ship" />
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def hauler(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-hauler" />
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def crate_small(assigns) do
    ~H"""
    <svg viewBox="0 0 16 16" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-crate_small" />
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def warehouse(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-warehouse" />
    </svg>
    """
  end

  attr :class, :any, default: "size-8"
  attr :rest, :global

  def dock(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-dock" />
    </svg>
    """
  end

  attr :class, :any, default: "w-full"
  attr :rest, :global

  def station_hub(assigns) do
    ~H"""
    <svg viewBox="0 0 64 32" class={["pixelated", @class]} aria-hidden="true" {@rest}>
      <use href="#sprite-station_hub" />
    </svg>
    """
  end
end
