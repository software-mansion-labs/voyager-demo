// The television scene.
//
// The server sends one JSON snapshot per second: who is docked, how much each
// of them shipped in the last second, how many haulers are on duty and how much
// they took away, and what the warehouse is doing - its mailbox depth, how many
// clerks are inspecting and how hard, and what is on the shelf, per cargo type.
// This hook turns that into ships flying in, containers landing on the intake
// dock, lanes lighting up as they are checksummed, one tile per container
// filling the hold, and haulers collecting from the far side.
//
// Two rules keep it honest and cheap:
//
//   * every crate in flight is a real delivery that happened, not decoration
//   * the number of crates in flight is capped, because at a busy moment the
//     station moves a few hundred containers a second and a booth television
//     cannot draw that many. Past the cap the counters do the talking.

// Inner column first: berths fill in order of arrival, visitors before
// freighters, so the people are nearest the station and a ship keeps its
// place for as long as it is docked. The inner column stops well short of the
// station's hull, so the containers have a stretch of open space to cross.
// The hull is 70% of the scene, centred: 15% to 85%. A ship is 5.5% wide.
const SHIP_COLUMNS = [9, 3.5];
const HAULER_COLUMNS = [91, 96.5];
const BERTH_SPACING = 14;
// Rows run from 16% to 84% of the scene: the DOCKED badge sits above the
// column and the top berth's label must not run into it.
const BERTH_SPREAD = 68;

// Eight berths to a column, and eight is the cap, so ships are one column and
// the second only exists for a cap somebody raises. Past eight rows the names
// start landing on each other.
const PER_COLUMN = 8;
const MAX_HAULERS_DRAWN = 8;

const SHIP_WIDTH = 5.5;

// What a name costs under a ship: 12px font, 4px padding, 4px gap, and a
// little air before the next hull.
const LABEL_HEIGHT = 24;

const MAX_CRATES_IN_FLIGHT = 90;
const MAX_CRATES_PER_SHIP_PER_TICK = 5;
const FLIGHT_MS = 850;

// How long a lane stays lit after a tick that saw it work. Lanes sit in a
// fixed grid of four by two - room for the whole crew at its cap - with square
// cells sized to the window, so one clerk and eight clerks draw the same box.
const LANE_BUSY_MS = 950;
const LANE_COLUMNS = 4;
const LANE_ROWS = 2;
const LANE_GAP = 3;

const CARGO_COLOR = {
  ice: "text-info",
  ore: "text-primary",
  machinery: "text-success",
  antimatter: "text-accent",
};

export const StationScene = {
  mounted() {
    this.actors = this.el.querySelector("[data-scene-actors]");
    this.station = this.el.querySelector("[data-scene-station]");
    this.hold = this.el.querySelector("[data-scene-hold]");
    this.lanes = this.el.querySelector("[data-scene-lanes]");
    this.figures = {
      memory: this.el.querySelector("[data-scene-memory]"),
      waiting: this.el.querySelector("[data-scene-waiting]"),
      laneCount: this.el.querySelector("[data-scene-lane-count]"),
      laneLabel: this.el.querySelector("[data-scene-lane-label]"),
      holdCount: this.el.querySelector("[data-scene-hold-count]"),
      hauled: this.el.querySelector("[data-scene-hauled]"),
      docked: this.el.querySelector("[data-scene-docked-count]"),
    };
    this.ports = {
      in: this.el.querySelector('[data-scene-port="in"]'),
      out: this.el.querySelector('[data-scene-port="out"]'),
    };

    this.ships = new Map();
    this.haulers = [];
    this.laneEls = [];
    this.tiles = new Map();
    this.holdCapacity = 0;
    this.outgoing = [];
    this.collected = null;
    this.pickupTurn = 0;
    this.inFlight = 0;
    this.crates = new Map();
    this.timers = new Set();

    this.apply();
  },

  updated() {
    this.apply();
  },

  destroyed() {
    this.timers.forEach(clearTimeout);
    this.timers.clear();
  },

  // --- state -------------------------------------------------------------

  apply() {
    let state;

    try {
      state = JSON.parse(this.el.dataset.scene);
    } catch (_error) {
      return;
    }

    this.sweepCrates();
    this.syncShips(state.ships);
    this.syncHaulers(state.haulers);
    this.paintStation(state);

    // The docks live on the station's walls, so where a crate is headed is
    // read off the page rather than written down as a constant.
    this.dock = { in: this.locate(this.ports.in), out: this.locate(this.ports.out) };

    this.trackCollected(state.collected);
    state.ships.forEach((ship) => this.launchCrates(ship));
    this.launchPickups(state.haulerDelta, state.haulers);
  },

  // What the haulers took since the last tick, as a list of cargo types with
  // one entry per container - the warehouse publishes the running totals per
  // type, so this is what actually left, not a guess from what the shelf lost.
  trackCollected(totals) {
    const previous = this.collected;
    this.collected = totals;
    this.outgoing = [];

    if (!previous) return;

    Object.entries(totals).forEach(([type, total]) => {
      const taken = Math.max(0, total - (previous[type] || 0));
      for (let n = 0; n < Math.min(taken, 24); n++) this.outgoing.push(type);
    });
  },

  // The cargo type the n-th outgoing crate of this tick is drawn in.
  outgoingTone(index) {
    if (this.outgoing.length === 0) return "text-primary";
    return CARGO_COLOR[this.outgoing[index % this.outgoing.length]] || "text-primary";
  },

  // --- ships -------------------------------------------------------------

  syncShips(ships) {
    const seen = new Set();

    ships.forEach((ship, index) => {
      seen.add(ship.id);

      const berth = this.berth(SHIP_COLUMNS, index, ships.length);
      let known = this.ships.get(ship.id);

      if (!known) {
        known = { el: this.spawnShip(ship, berth), berth };
        this.ships.set(ship.id, known);
      } else {
        known.berth = berth;
        known.el.style.left = `${berth.x}%`;
        known.el.style.top = `${berth.y}%`;
        known.el.dataset.lane = berth.lane;
      }

      this.size(known.el, berth.spacing);
      known.cargo = ship.cargo;
    });

    this.ships.forEach((known, id) => {
      if (seen.has(id)) return;

      this.ships.delete(id);
      known.el.classList.remove("scene-ship-arriving");
      known.el.classList.add("scene-ship-leaving");
      this.after(1100, () => known.el.remove());
    });
  },

  spawnShip(ship, berth) {
    const el = document.createElement("div");
    el.className = `scene-actor scene-ship-arriving ${CARGO_COLOR[ship.cargo] || ""}`;
    el.style.left = `${berth.x}%`;
    el.style.top = `${berth.y}%`;
    el.dataset.lane = berth.lane;

    // The name is the whole reason a visitor is looking at this screen, so it
    // is never truncated: it sits under the ship and runs as wide as it likes.
    el.innerHTML = `
      <div class="scene-hover relative" style="animation-delay: ${Math.round(berth.y * 13) % 2400}ms">
        <span class="scene-thruster"></span>
        ${this.sprite("ship")}
        <p class="scene-ship-label">${escapeHtml(ship.label)}</p>
      </div>
    `;

    this.actors.appendChild(el);
    this.after(1400, () => el.classList.remove("scene-ship-arriving"));

    return el;
  },

  // Every ship is drawn the same, at full size - unless the column is so full
  // that a full-size hull would paint over the name of the ship above it.
  size(el, spacing) {
    el.style.width = `${Math.min(SHIP_WIDTH, this.fits(spacing))}%`;
  },

  // A sprite is square, so a berth row thirty pixels below the last one cannot
  // hold a forty pixel ship and its name: past a certain crowd the whole column
  // has to shrink, or every ship paints over the name of the one above it. Widths
  // here are a percentage of the scene's width and the row pitch is of its
  // height, hence the conversion.
  fits(spacing) {
    const box = this.el.getBoundingClientRect();

    if (!spacing || !box.width) return SHIP_WIDTH;

    return ((spacing * box.height) / 100 - LABEL_HEIGHT) / box.width * 100;
  },

  // --- haulers -----------------------------------------------------------

  syncHaulers(count) {
    const wanted = Math.min(count, MAX_HAULERS_DRAWN);

    while (this.haulers.length > wanted) {
      const el = this.haulers.pop();
      el.classList.add("scene-hauler-leaving");
      this.after(1100, () => el.remove());
    }

    while (this.haulers.length < wanted) {
      const el = document.createElement("div");
      el.className = "scene-actor text-base-content";
      el.style.width = "5%";
      el.innerHTML = `<div class="scene-hover">${this.sprite("hauler")}</div>`;
      this.actors.appendChild(el);
      this.haulers.push(el);
    }

    this.haulers.forEach((el, index) => {
      const berth = this.berth(HAULER_COLUMNS, index, this.haulers.length);
      el.style.left = `${berth.x}%`;
      el.style.top = `${berth.y}%`;
    });
  },

  // --- cargo in flight ---------------------------------------------------

  launchCrates(ship) {
    if (ship.delta <= 0) return;

    const known = this.ships.get(ship.id);
    if (!known) return;

    const count = Math.min(ship.delta, MAX_CRATES_PER_SHIP_PER_TICK);
    const gap = 900 / count;

    for (let n = 0; n < count; n++) {
      this.after(Math.round(n * gap), () => {
        const nose = { x: known.berth.x + 2.5, y: known.berth.y };
        this.flyCrate(nose, this.dock.in, CARGO_COLOR[ship.cargo] || "");
      });
    }
  },

  launchPickups(delta, haulers) {
    if (delta <= 0 || haulers === 0) return;

    // One crate per pickup, roughly - a batch is two containers - spread over
    // the second, up to a dozen; past that the OUTBOUND count carries it.
    const count = Math.min(Math.ceil(delta / 2), 12);
    const gap = 900 / count;

    for (let n = 0; n < count; n++) {
      this.after(Math.round(n * gap), () => {
        // The turn counter lives across ticks. Indexed from the loop variable,
        // every tick started back at zero - and at one crate per tick, which is
        // what the current pace mostly produces, the first hauler took every
        // delivery while the other two hung there as scenery.
        const target = this.haulers[this.pickupTurn++ % this.haulers.length];
        if (!target) return;

        this.flyCrate(
          this.dock.out,
          { x: parseFloat(target.style.left), y: parseFloat(target.style.top) },
          this.outgoingTone(n),
        );
      });
    }
  },

  flyCrate(from, to, tone) {
    // A hidden tab freezes both timers and animations, so a screensaver or a
    // window in front of the television would otherwise fill the scene with
    // crates that never arrive and never clean up.
    if (document.hidden || this.inFlight >= MAX_CRATES_IN_FLIGHT) return;

    this.inFlight++;

    const el = document.createElement("div");
    el.className = `scene-crate ${tone}`;
    el.style.width = "3%";
    el.style.left = `${from.x}%`;
    el.style.top = `${from.y}%`;
    el.innerHTML = this.sprite("container");
    this.actors.appendChild(el);

    // A shallow arc, so a stream of them reads as a flight path rather than a
    // straight line of dots. Stepped easing keeps it on the pixel grid.
    const lift = from.y > to.y ? -5 : 5;
    const animation = el.animate(
      [
        { left: `${from.x}%`, top: `${from.y}%`, opacity: 0.35 },
        { left: `${(from.x + to.x) / 2}%`, top: `${(from.y + to.y) / 2 + lift}%`, opacity: 1, offset: 0.5 },
        { left: `${to.x}%`, top: `${to.y}%`, opacity: 1 },
      ],
      { duration: FLIGHT_MS, easing: "steps(20, end)" },
    );

    const done = () => {
      if (!this.crates.delete(el)) return;
      el.remove();
      this.inFlight--;
    };

    this.crates.set(el, done);
    animation.onfinish = done;
    animation.oncancel = done;
  },

  // Belt and braces: anything still in the air well past its flight time never
  // got its finish event, so sweep it. Without this one missed callback leaks a
  // slot out of the budget for as long as the television is up.
  sweepCrates() {
    if (this.crates.size < MAX_CRATES_IN_FLIGHT) return;

    this.crates.forEach((done, el) => {
      if (el.getAnimations().length === 0) done();
    });
  },

  // --- the station -------------------------------------------------------

  paintStation(state) {
    const stored = Object.values(state.hold).reduce((sum, count) => sum + count, 0);

    this.figures.memory.textContent = formatBytes(state.memory);
    this.figures.waiting.textContent = formatCount(state.waiting);
    this.figures.hauled.textContent = formatCount(state.hauled);
    this.figures.holdCount.textContent = `${formatCount(stored)} / ${formatCount(state.capacity)}`;
    this.figures.laneCount.textContent = formatCount(state.lanes);
    this.figures.laneLabel.textContent = state.lanes === 1 ? "clerk" : "clerks";
    this.figures.docked.textContent = `${state.docked}/${state.berths}`;

    // The mailbox depth turns red at the same line the phones call congested.
    this.figures.waiting.classList.toggle("text-error", Boolean(state.congested));
    this.figures.waiting.classList.toggle("text-warning", !state.congested);

    this.station.classList.toggle("is-full", Boolean(state.full));

    this.sizeHold(state.capacity);
    this.syncLanes(state.lanes, state.inspectedDelta);
    this.syncHold(state.hold);
  },

  // One cell per container the warehouse can hold, in a grid shaped like the
  // window it fills. The tiles flow down columns from the outbound wall, so the
  // row count is what fixes the layout; the columns follow from the capacity.
  // Recomputed only when the capacity changes, which is a config edit and a
  // restart.
  sizeHold(capacity) {
    if (capacity === this.holdCapacity) return;

    this.holdCapacity = capacity;
    const box = this.hold.getBoundingClientRect();
    const ratio = box.width > 0 && box.height > 0 ? box.width / box.height : 4;
    const rows = gridRows(Math.max(capacity, 1), ratio);
    const columns = Math.max(1, Math.ceil(capacity / rows));
    this.hold.style.gridTemplateRows = `repeat(${rows}, 1fr)`;
    this.hold.style.gridTemplateColumns = `repeat(${columns}, 1fr)`;
  },

  // One lane per clerk on shift, every one of them. A tick that inspected N
  // containers lights N lanes for a moment; under load the single clerk's lane
  // never goes dark.
  syncLanes(count, inspected) {
    const wanted = Math.max(count, 0);
    this.sizeLanes();

    while (this.laneEls.length > wanted) {
      this.laneEls.pop().remove();
    }

    while (this.laneEls.length < wanted) {
      const el = document.createElement("div");
      el.className = "scene-lane";
      el.innerHTML = this.sprite("container");
      this.lanes.appendChild(el);
      this.laneEls.push(el);
    }

    const busy = Math.min(inspected, this.laneEls.length);

    this.laneEls.forEach((el, index) => {
      if (index >= busy) return;

      el.classList.add("is-busy");
      clearTimeout(el.busyTimer);
      el.busyTimer = setTimeout(() => el.classList.remove("is-busy"), LANE_BUSY_MS);
    });
  },

  // Square cells, four by two, as large as the window allows in both directions.
  sizeLanes() {
    const box = this.lanes.getBoundingClientRect();
    if (!box.width || !box.height) return;

    const byWidth = (box.width - LANE_GAP * (LANE_COLUMNS - 1)) / LANE_COLUMNS;
    const byHeight = (box.height - LANE_GAP * (LANE_ROWS - 1)) / LANE_ROWS;
    const cell = Math.max(8, Math.floor(Math.min(byWidth, byHeight)));

    this.lanes.style.gridTemplateColumns = `repeat(${LANE_COLUMNS}, ${cell}px)`;
    this.lanes.style.gridTemplateRows = `repeat(${LANE_ROWS}, ${cell}px)`;
  },

  // One tile per container on the shelf, in its cargo colour. Only the
  // difference is touched: a tick adds a few tiles and takes a few away, and
  // the oldest of a type goes first, the way the warehouse's own queue works.
  syncHold(hold) {
    Object.entries(hold).forEach(([type, count]) => {
      let tiles = this.tiles.get(type);

      if (!tiles) {
        tiles = [];
        this.tiles.set(type, tiles);
      }

      while (tiles.length > count) {
        tiles.shift().remove();
      }

      while (tiles.length < count) {
        const el = document.createElement("span");
        el.className = `scene-tile ${CARGO_COLOR[type] || "text-base-content"}`;
        this.hold.appendChild(el);
        tiles.push(el);
      }
    });
  },

  // --- helpers -----------------------------------------------------------

  // Berths run down two columns so twenty five ships still fit on a screen
  // without becoming a wall of sprites. Rows are centred rather than spread to
  // the edges: three haulers pinned to the top and bottom corners read as a
  // layout bug, not as a crew.
  berth(columns, index, total) {
    const lanes = Math.min(Math.ceil(Math.max(total, 1) / PER_COLUMN), columns.length);
    const perColumn = Math.ceil(Math.max(total, 1) / lanes);
    const column = Math.floor(index / perColumn);
    const row = index % perColumn;
    const spacing = perColumn > 1 ? Math.min(BERTH_SPACING, BERTH_SPREAD / (perColumn - 1)) : 0;

    const lane = Math.min(column, lanes - 1);

    // Columns share their rows exactly: a name belongs to the ship straight
    // above it, and a stagger would set it beside a ship in the next column.
    return {
      lane,
      spacing,
      x: columns[lane],
      y: 50 + (row - (perColumn - 1) / 2) * spacing,
    };
  },

  sprite(name) {
    return `<svg viewBox="0 0 16 16" class="pixelated w-full"><use href="#sprite-${name}"></use></svg>`;
  },

  // Where an element sits, as a percentage of the scene - the coordinate
  // system every flight is drawn in.
  locate(el) {
    const scene = this.el.getBoundingClientRect();
    const box = el.getBoundingClientRect();

    if (!scene.width || !scene.height) return { x: 50, y: 50 };

    return {
      x: ((box.left + box.width / 2 - scene.left) / scene.width) * 100,
      y: ((box.top + box.height / 2 - scene.top) / scene.height) * 100,
    };
  },

  after(delay, fun) {
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      fun();
    }, delay);

    this.timers.add(timer);
  },
};

// A row count near the one the window's shape asks for that divides the
// capacity exactly, so a full warehouse is a full grid with no empty slots in
// the last column. Falls back to the nearest count when nothing divides.
function gridRows(capacity, ratio) {
  const ideal = Math.max(1, Math.round(Math.sqrt(capacity / ratio)));

  for (let offset = 0; offset <= ideal; offset++) {
    for (const rows of [ideal - offset, ideal + offset]) {
      if (rows >= 1 && capacity % rows === 0) return rows;
    }
  }

  return ideal;
}

// The same units and rounding as the server's format_bytes, so a number on
// the station matches the same number on a phone.
function formatBytes(bytes) {
  const value = Number(bytes || 0);

  if (value < 1024) return `${Math.round(value)} B`;
  if (value < 1048576) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1073741824) return `${(value / 1048576).toFixed(1)} MB`;
  return `${(value / 1073741824).toFixed(2)} GB`;
}

// Thousands grouped with a space, the way the phones do it - a no-break one,
// so a figure in a narrow window shrinks rather than wraps.
function formatCount(value) {
  return String(Math.trunc(Number(value || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, "\u00a0");
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char];
  });
}
