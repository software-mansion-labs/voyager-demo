// The television scene.
//
// The server sends one JSON snapshot per second: who is docked, how much each
// of them shipped in the last second, how many haulers are on duty and how much
// they took away, and how full the warehouse is. This hook turns that into
// ships flying in, containers crossing the gap one at a time, haulers pulling
// them out the other side, and a bay window filling up in the middle.
//
// Two rules keep it honest and cheap:
//
//   * every crate in flight is a real delivery that happened, not decoration
//   * the number of crates in flight is capped, because at a busy moment the
//     station moves a few hundred containers a second and a booth television
//     cannot draw that many. Past the cap the counters do the talking.

const LEFT_PORT = { x: 28, y: 50 };
const RIGHT_PORT = { x: 72, y: 50 };

// Inner column first: berths fill in order of arrival, visitors before
// freighters, so the people are nearest the station and a ship keeps its
// place for as long as it is docked. The inner column stops well short of the
// station's hull, so the containers have a stretch of open space to cross.
const SHIP_COLUMNS = [17, 7];
const HAULER_COLUMNS = [88, 78];
const BERTH_SPACING = 14;
const BERTH_SPREAD = 76;

// A column takes eight before the next one opens: two columns is the cap.
// Past that the rows are closer together than a ship is tall, and the names
// start landing on each other.
const PER_COLUMN = 8;

const SHIP_WIDTH = 5.5;

// Roughly what a name costs under a ship: font, padding and the gap above it.
const LABEL_HEIGHT = 15;

const MAX_CRATES_IN_FLIGHT = 90;
const MAX_CRATES_PER_SHIP_PER_TICK = 5;
const FLIGHT_MS = 850;

const CARGO_COLOR = {
  ice: "text-info",
  ore: "text-primary",
  machinery: "text-warning",
  antimatter: "text-accent",
};

export const StationScene = {
  mounted() {
    this.actors = this.el.querySelector("[data-scene-actors]");
    this.bay = this.el.querySelector("[data-scene-bay]");
    this.ports = {
      in: this.el.querySelector('[data-scene-port="in"]'),
      out: this.el.querySelector('[data-scene-port="out"]'),
    };

    this.ships = new Map();
    this.haulers = [];
    this.pickupTurn = 0;
    this.inFlight = 0;
    this.crates = new Map();
    this.timers = new Set();

    this.buildBay();
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
    this.paintBay(state.stored, state.full);

    state.ships.forEach((ship) => this.launchCrates(ship));
    this.launchPickups(state.haulerDelta, state.haulers);
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
    // is never truncated. Instead the two columns hang their labels on opposite
    // sides of the ship, so a long name can run as wide as it likes without
    // colliding with its neighbour.
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
    const wanted = Math.min(count, 12);

    while (this.haulers.length > wanted) {
      const el = this.haulers.pop();
      el.classList.add("scene-hauler-leaving");
      this.after(1100, () => el.remove());
    }

    while (this.haulers.length < wanted) {
      const el = document.createElement("div");
      el.className = "scene-actor text-success";
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
        this.flyCrate(nose, LEFT_PORT, CARGO_COLOR[ship.cargo] || "");
      });
    }
  },

  launchPickups(delta, haulers) {
    if (delta <= 0 || haulers === 0) return;

    const count = Math.min(Math.ceil(delta / 2), 6);

    for (let n = 0; n < count; n++) {
      this.after(n * 140, () => {
        // The turn counter lives across ticks. Indexed from the loop variable,
        // every tick started back at zero - and at one crate per tick, which is
        // what the current pace mostly produces, the first hauler took every
        // delivery while the other two hung there as scenery.
        const target = this.haulers[this.pickupTurn++ % this.haulers.length];
        if (!target) return;

        this.flyCrate(
          RIGHT_PORT,
          { x: parseFloat(target.style.left), y: parseFloat(target.style.top) },
          "text-success",
          "out",
        );
      });
    }
  },

  flyCrate(from, to, tone, port = "in") {
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
      this.flashPort(port);
    };

    this.crates.set(el, done);
    animation.onfinish = done;
    animation.oncancel = done;
  },

  // A short flare where the cargo lands. Under load it stays lit, which is
  // exactly what a port moving forty containers a second should look like.
  flashPort(which) {
    const el = this.ports[which];
    if (!el) return;

    el.classList.add("is-hot");
    this.after(140, () => el.classList.remove("is-hot"));
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

  // --- the bay -------------------------------------------------------------

  buildBay() {
    this.bayCells = [];

    for (let n = 0; n < 96; n++) {
      const cell = document.createElement("span");
      this.bay.appendChild(cell);
      this.bayCells.push(cell);
    }
  },

  // What the warehouse is holding, drawn inside the station's own bay window.
  // The first container lights the first cell - rounding to nearest left the
  // window dark for the first sixty deliveries, which read as cargo vanishing.
  // Red means full: the oldest cargo is going over the side.
  paintBay(ratio, full) {
    const clamped = Math.min(Math.max(ratio, 0), 1);
    const filled = clamped > 0 ? Math.max(1, Math.ceil(clamped * this.bayCells.length)) : 0;

    this.bay.classList.toggle("text-error", full);
    this.bay.classList.toggle("text-primary", !full);

    // Filled from the bottom up, the way a warehouse actually fills.
    const floor = this.bayCells.length - filled;

    this.bayCells.forEach((cell, index) => {
      cell.style.opacity = index >= floor ? "1" : "0.08";
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

    // The second column sits half a row lower than the first, so a long name in
    // one column falls into the gap between two ships of the other instead of
    // across a neighbour's label.
    return {
      lane,
      spacing,
      x: columns[lane],
      y: 50 + (row - (perColumn - 1) / 2) * spacing + (lane % 2) * spacing * 0.5,
    };
  },

  sprite(name) {
    return `<svg viewBox="0 0 16 16" class="pixelated w-full"><use href="#sprite-${name}"></use></svg>`;
  },

  after(delay, fun) {
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      fun();
    }, delay);

    this.timers.add(timer);
  },
};

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char];
  });
}
