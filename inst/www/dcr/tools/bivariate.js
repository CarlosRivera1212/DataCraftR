/* Bivariate normal tool: one ellipse per group (up to 10).
 * Undoable state (this.state, plain JSON):
 *   {groups: [names], names: {x, y, group}, n, xlim: [a, b], ylim: [a, b],
 *    ell: [{mx, my, s1, s2, th}, ...]}
 * (mx, my) is the centre, s1 the sd along the angle th (radians), s2 the sd
 * perpendicular to it, all in data units. The spec stores the equivalent
 * marginal form (means, sds, correlation: toMarginal()).
 * Settings (this.ui, not undoable): {active, mode, autofit}; lim0 keeps the
 * initial limits for "Reset axes". Handles mode: centre moves, the major
 * handle sets s1 and rotates (relative to the grab), the minor handle sets
 * s2. The gestures mode value is accepted and behaves like handles until the
 * gesture layer exists. One drag = one stroke = one history entry. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MODES = ["handles", "gestures"];
  var MARGIN = { top: 14, right: 16, bottom: 40, left: 50 };
  var DEAD_ZONE = 3;          // px: a press that moves less than this is a click
  var RHO_MAX = 0.999;
  var N_ELLIPSE = 96;
  var RHO_CYCLE = [0.5, -0.5, 0];

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function copy(x) { return JSON.parse(JSON.stringify(x)); }

  // Valid group names, trimmed like R's check_names(), or null.
  function cleanNames(x) {
    var out = DCR.asArray(x).map(trim);
    if (out.length < 1 || out.length > 10) return null;
    for (var i = 0; i < out.length; i++) {
      if (!out[i] || out.indexOf(out[i]) !== i) return null;
    }
    return out;
  }

  // Two finite increasing numbers, or null.
  function cleanRange(x) {
    var a = DCR.asArray(x);
    // a blank field (null / "") is not 0
    if (a.some(function (v) { return v === null || v === "" || typeof v === "boolean"; })) return null;
    var r = a.map(Number);
    if (r.length !== 2 || !isFinite(r[0]) || !isFinite(r[1]) || !(r[0] < r[1])) return null;
    return r;
  }

  function cleanWhole(x, lo, hi) {
    var v = Array.isArray(x) ? NaN : Number(x);
    return x !== null && x !== "" && typeof x !== "boolean" && isFinite(v) &&
      v === Math.round(v) && v >= lo && v <= hi ? v : null;
  }

  function cleanVarNames(x) {
    if (!x || typeof x !== "object") return null;
    var v = cleanNames([x.x, x.y, x.group].map(function (s) { return s == null ? "" : s; }));
    return v && v.length === 3 ? { x: v[0], y: v[1], group: v[2] } : null;
  }

  // Map old group indices to new ones: names present in both are kept; with
  // the same number of groups the rest are renames (paired in order).
  function remapGroups(oldGroups, newGroups) {
    var map = oldGroups.map(function (g) { return newGroups.indexOf(g); });
    if (oldGroups.length === newGroups.length) {
      var free = newGroups.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  // ---- Pure geometry (exposed for tests) -----------------------------------
  function toMarginal(e) {
    var c = Math.cos(e.th), s = Math.sin(e.th);
    var a = e.s1 * e.s1, b = e.s2 * e.s2;
    var vx = a * c * c + b * s * s, vy = a * s * s + b * c * c;
    var cov = (a - b) * s * c;
    var rho = cov / Math.sqrt(vx * vy);
    if (!isFinite(rho)) rho = 0;
    return { mean_x: e.mx, mean_y: e.my, sd_x: Math.sqrt(vx), sd_y: Math.sqrt(vy),
             rho: clamp(rho, -RHO_MAX, RHO_MAX) };
  }

  function fromMarginal(m) {
    var vx = m.sd_x * m.sd_x, vy = m.sd_y * m.sd_y;
    var rho = clamp(m.rho, -RHO_MAX, RHO_MAX);
    var cov = rho * m.sd_x * m.sd_y;
    var half = (vx + vy) / 2, disc = Math.sqrt(Math.pow((vx - vy) / 2, 2) + cov * cov);
    var v1 = half + disc, v2 = Math.max(half - disc, v1 * 1e-12);
    return { mx: m.mean_x, my: m.mean_y, s1: Math.sqrt(v1), s2: Math.sqrt(v2),
             th: 0.5 * Math.atan2(2 * cov, vx - vy) };
  }

  function smaller(xlim, ylim) { return Math.min(xlim[1] - xlim[0], ylim[1] - ylim[0]); }

  // One ellipse (sd 10 % of the smaller range, given rho) at (cx, cy).
  function ellipseAt(cx, cy, m, rho) {
    return fromMarginal({ mean_x: cx, mean_y: cy, sd_x: 0.1 * m, sd_y: 0.1 * m, rho: rho });
  }

  // Initial ellipses: one group at the view centre; k > 1 on a circle of
  // radius 0.25 m, first at the top, clockwise. `groups` is a name list or a
  // count.
  function initial(groups, xlim, ylim) {
    var k = Array.isArray(groups) ? groups.length : Number(groups);
    var m = smaller(xlim, ylim);
    var cx = (xlim[0] + xlim[1]) / 2, cy = (ylim[0] + ylim[1]) / 2, out = [];
    for (var i = 0; i < k; i++) {
      var x = cx, y = cy;
      if (k > 1) {
        var a = Math.PI / 2 - 2 * Math.PI * i / k;
        x = cx + 0.25 * m * Math.cos(a);
        y = cy + 0.25 * m * Math.sin(a);
      }
      out.push(ellipseAt(x, y, m, RHO_CYCLE[i % 3]));
    }
    return out;
  }

  // 2-sigma bounding box of an ellipse.
  function box(e) {
    var g = toMarginal(e);
    return { xlo: g.mean_x - 2 * g.sd_x, xhi: g.mean_x + 2 * g.sd_x,
             ylo: g.mean_y - 2 * g.sd_y, yhi: g.mean_y + 2 * g.sd_y };
  }

  function boxes(ell) {
    var b = { xlo: Infinity, xhi: -Infinity, ylo: Infinity, yhi: -Infinity };
    ell.forEach(function (e) {
      var q = box(e);
      b.xlo = Math.min(b.xlo, q.xlo); b.xhi = Math.max(b.xhi, q.xhi);
      b.ylo = Math.min(b.ylo, q.ylo); b.yhi = Math.max(b.yhi, q.yhi);
    });
    return b;
  }

  function tidy(v) { return Number(v.toPrecision(12)); }

  // Extend lim to cover [lo, hi], then round only the moved ends outward to a
  // multiple of step = 10^floor(log10(span)) / 2. Never shrinks.
  function fitLimits(lim, lo, hi) {
    var a = lim[0], b = lim[1];
    var moveA = isFinite(lo) && lo < a, moveB = isFinite(hi) && hi > b;
    if (!moveA && !moveB) return [a, b];
    if (moveA) a = lo;
    if (moveB) b = hi;
    var step = Math.pow(10, Math.floor(Math.log10(b - a))) / 2;
    if (moveA) {
      a = Math.floor(a / step) * step;
      while (a > lo) a -= step;
      a = Math.min(tidy(a), lim[0]);
    }
    if (moveB) {
      b = Math.ceil(b / step) * step;
      while (b < hi) b += step;
      b = Math.max(tidy(b), lim[1]);
    }
    return [a, b];
  }

  // Does the view hold every group's 2-sigma box?
  function contains(xlim, ylim, ell) {
    var b = boxes(ell);
    var ex = 1e-9 * (xlim[1] - xlim[0]), ey = 1e-9 * (ylim[1] - ylim[0]);
    return b.xlo >= xlim[0] - ex && b.xhi <= xlim[1] + ex &&
      b.ylo >= ylim[0] - ey && b.yhi <= ylim[1] + ey;
  }

  function meanOutside(xlim, ylim, ell) {
    return ell.some(function (e) {
      return e.mx < xlim[0] || e.mx > xlim[1] || e.my < ylim[0] || e.my > ylim[1];
    });
  }

  // View limits grown (never shrunk) to hold every group's 2-sigma box.
  function expandTo(xlim, ylim, ell) {
    var b = boxes(ell);
    return { xlim: fitLimits(xlim, b.xlo, b.xhi), ylim: fitLimits(ylim, b.ylo, b.yhi) };
  }

  // Keep |rho| <= 0.999 for any angle: s_other * RATIO <= s <= s_other / RATIO
  // (so what is drawn is what is sampled), within [smin, smax].
  var RATIO = 0.02237;
  function clampSd(v, other, smin, smax) {
    return clamp(v, Math.max(smin, RATIO * other), Math.min(smax, other / RATIO));
  }

  // Distance from (x, y) along (dx, dy) to the edge of the view.
  function reach(x, y, dx, dy, xlim, ylim) {
    var t = Infinity;
    if (dx > 1e-12) t = Math.min(t, (xlim[1] - x) / dx);
    else if (dx < -1e-12) t = Math.min(t, (xlim[0] - x) / dx);
    if (dy > 1e-12) t = Math.min(t, (ylim[1] - y) / dy);
    else if (dy < -1e-12) t = Math.min(t, (ylim[0] - y) / dy);
    return t;
  }

  // Autofit off: a dragged sd is capped so its handle stays inside the view.
  function capSd(v, x, y, dx, dy, s, smin) {
    return Math.max(smin, Math.min(v, reach(x, y, dx, dy, s.xlim, s.ylim)));
  }

  var Bivariate = DCR.extend(DCR.Tool, {
    init: function (o) {
      this.ui = {
        active: 0,
        mode: MODES.indexOf(o.mode) >= 0 ? o.mode : "handles",
        autofit: o.autofit === undefined ? true : o.autofit !== false
      };
      this.lim0 = { xlim: cleanRange(o.xlim) || [0, 10], ylim: cleanRange(o.ylim) || [0, 10] };
    },

    initialState: function (o) {
      var groups = cleanNames(o.groups) || ["A", "B"];
      var xlim = cleanRange(o.xlim) || [0, 10], ylim = cleanRange(o.ylim) || [0, 10];
      var n = cleanWhole(o.n, 1, 1e6) || 200;
      if (n * groups.length > 1e6) n = Math.floor(1e6 / groups.length);
      return {
        groups: groups,
        names: cleanVarNames(o.names) || { x: "x", y: "y", group: "group" },
        n: n,
        xlim: xlim,
        ylim: ylim,
        ell: initial(groups, xlim, ylim)
      };
    },

    toSpec: function () {
      var s = this.state, g = s.ell.map(toMarginal);
      function col(k) { return g.map(function (m) { return m[k]; }); }
      return {
        tool: "bivariate",
        groups: s.groups.slice(),
        names: { x: s.names.x, y: s.names.y, group: s.names.group },
        xlim: s.xlim.slice(),
        ylim: s.ylim.slice(),
        mean_x: col("mean_x"), mean_y: col("mean_y"),
        sd_x: col("sd_x"), sd_y: col("sd_y"), rho: col("rho"),
        n: s.n
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.groups.length - 1);
    },

    controls: function () {
      var s = this.state;
      return {
        groups: { value: s.groups.join(", ") },
        active: {
          choices: s.groups.map(function (g, i) {
            return { value: String(i + 1), label: g, color: DCR.palette[i % 10] };
          }),
          value: String(this.activeIndex() + 1)
        },
        mode: { value: this.ui.mode },
        autofit: { value: this.ui.autofit },
        n: { value: s.n },
        xlim: { value: s.xlim.slice() },
        ylim: { value: s.ylim.slice() },
        names: { value: { x: s.names.x, y: s.names.y, group: s.names.group } }
      };
    },

    // A control value in tool units, or null when invalid. Accepts both what
    // R forwards and what controls() pushes (groups as "A, B" text).
    controlValue: function (key, value) {
      var v, s = this.state;
      switch (key) {
        case "groups":
          v = cleanNames(typeof value === "string" ? value.split(",") : value);
          return v;
        case "active":
          v = parseInt(value, 10) - 1;
          return v >= 0 && v < s.groups.length ? v : null;
        case "mode":
          return MODES.indexOf(value) >= 0 ? value : null;
        case "autofit":
          return typeof value === "boolean" ? value : null;
        case "n":
          return cleanWhole(value, 1, 1e6);
        case "xlim":
        case "ylim":
          return cleanRange(value);
        case "names":
          return cleanVarNames(value);
      }
      return null;
    },

    setControl: function (key, value) {
      var s = this.state, ui = this.ui, v = this.controlValue(key, value);
      if (v === null) return;
      switch (key) {
        case "groups":
          if (same(v, s.groups)) break;
          if (this._tooMany(s.n, v.length)) return;
          this._setGroups(v);
          break;
        case "active":
          if (v !== ui.active) {
            ui.active = v;
            this.render();
          }
          break;
        case "mode":
        case "autofit":
          if (v !== ui[key]) {
            ui[key] = v;
            this._requestDraw();
          }
          break;
        case "n":
          if (v === s.n) break;
          if (this._tooMany(v, s.groups.length)) return;
          this._commitWith(key, v);
          break;
        case "names":
          if (!same(v, s[key])) this._commitWith(key, v);
          break;
        case "xlim":
          this._applyLimits(v, s.ylim);
          break;
        case "ylim":
          this._applyLimits(s.xlim, v);
          break;
      }
    },

    // n x groups over 1e6 rows: refuse, say so and put the sidebar back.
    _tooMany: function (n, k) {
      if (n * k <= 1e6) return false;
      this._flash("n x groups must be at most 1e6 (" + n + " x " + k + ")");
      this.syncControls();
      return true;
    },

    _commitWith: function (key, value) {
      var next = DCR.deepCopy(this.state);
      next[key] = value;
      this.commit(next);
    },

    // New view limits as one history entry; when a mean would fall outside,
    // both limits grow to hold every group's 2-sigma box and the canvas says so.
    _applyLimits: function (xlim, ylim) {
      var s = this.state, next = DCR.deepCopy(s), out = meanOutside(xlim, ylim, s.ell);
      var lim = out ? expandTo(xlim, ylim, s.ell) : { xlim: xlim, ylim: ylim };
      var grew = out && (!same(lim.xlim, xlim) || !same(lim.ylim, ylim));
      next.xlim = lim.xlim;
      next.ylim = lim.ylim;
      if (!same(next.xlim, s.xlim) || !same(next.ylim, s.ylim)) this.commit(next);
      else this.syncControls();
      if (grew) this._flash("Axes expanded to keep every group in view");
    },

    // New group list: ellipses keep their values by name (renames pair in
    // order); new groups start at the view centre.
    _setGroups: function (groups) {
      var s = this.state, map = remapGroups(s.groups, groups);
      var m = smaller(s.xlim, s.ylim);
      var cx = (s.xlim[0] + s.xlim[1]) / 2, cy = (s.ylim[0] + s.ylim[1]) / 2;
      var ell = groups.map(function () { return ellipseAt(cx, cy, m, 0); });
      var gone = [];
      map.forEach(function (j, i) {
        if (j >= 0) ell[j] = copy(s.ell[i]);
        else gone.push(s.groups[i]);
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      var next = DCR.deepCopy(s);
      next.groups = groups;
      next.ell = ell;
      this.commit(next);
      if (gone.length) this._flash(gone.join(", ") + " removed \u2014 Ctrl+Z to undo");
    },

    // Clear: every group back to the initial layout; no entry when unchanged.
    clear: function () {
      var s = this.state, ell = initial(s.groups, s.xlim, s.ylim);
      if (same(ell, s.ell)) return;
      var next = DCR.deepCopy(s);
      next.ell = ell;
      this.commit(next);
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name);
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.groups.length && k !== this.ui.active) {
          this.ui.active = k;
          this.render();
          this.syncControls();
        }
      } else if (name === "reset-axes") {
        this._applyLimits(this.lim0.xlim.slice(), this.lim0.ylim.slice());
      }
    },

    // ---- Pointer geometry ------------------------------------------------------
    _unit: function () {
      var s = this.state;
      return smaller(s.xlim, s.ylim) / 10;
    },

    _handles: function (e) {
      var c = Math.cos(e.th), s = Math.sin(e.th);
      return {
        major: { x: e.mx + e.s1 * c, y: e.my + e.s1 * s },
        minor: { x: e.mx - e.s2 * s, y: e.my + e.s2 * c }
      };
    },

    // Is p within the 2-sigma ellipse of e?
    _inside2: function (e, p) {
      var dx = p.x - e.mx, dy = p.y - e.my, c = Math.cos(e.th), s = Math.sin(e.th);
      var a = (dx * c + dy * s) / e.s1, b = (-dx * s + dy * c) / e.s2;
      return Math.sqrt(a * a + b * b) <= 2;
    },

    // What is under p: {kind: "major" | "minor" | "move"} for the active
    // group's handles, {kind: "select", i} for another group, or null.
    _hit: function (p) {
      var s = this.state, i = this.activeIndex(), e = s.ell[i], HIT = 0.28 * this._unit();
      var h = this._handles(e);
      function d(q) { return Math.hypot(p.x - q.x, p.y - q.y); }
      // the nearest of major, minor and centre within HIT wins, so a thin
      // ellipse's centre stays grabbable
      var best = null, bd = HIT;
      [["major", h.major], ["minor", h.minor], ["move", { x: e.mx, y: e.my }]].forEach(function (c) {
        var dist = d(c[1]);
        if (dist < bd) { bd = dist; best = { kind: c[0], i: i }; }
      });
      if (best) return best;
      for (var j = 0; j < s.ell.length; j++) {
        if (j !== i && this._inside2(s.ell[j], p)) return { kind: "select", i: j };
      }
      return null;
    },

    // ---- Pointer strokes: one drag = one history entry -------------------------
    _pointerDown: function (ev) {
      if (ev.button !== 0 || !this._geo) return;
      if (this._stroke) {
        // a stroke whose end event never came (lost capture): finish it first
        var old = this._stroke, svg = this._dom.svg;
        var held = typeof svg.hasPointerCapture === "function" && svg.hasPointerCapture(old.id);
        if (ev.pointerId !== old.id && held) return;
        this._pointerUp({ pointerId: old.id });
      }
      var p = this._toData(ev), hit = this._hit(p);
      if (!hit) return;
      if (hit.kind === "select") {
        this.ui.active = hit.i;
        this._requestDraw();
        this.syncControls();
        return;
      }
      this._dom.svg.setPointerCapture(ev.pointerId);
      var e = this.state.ell[hit.i];
      this._stroke = {
        id: ev.pointerId, kind: hit.kind, i: hit.i, moved: false,
        cx: ev.clientX, cy: ev.clientY,
        start: copy(e), off: { x: e.mx - p.x, y: e.my - p.y },
        ang: Math.atan2(p.y - e.my, p.x - e.mx), acc: 0,
        r0: Math.hypot(p.x - e.mx, p.y - e.my)
      };
      // minor handle: signed projection of the grab on the minor axis
      var qn = { x: -Math.sin(e.th), y: Math.cos(e.th) };
      this._stroke.q0 = (p.x - e.mx) * qn.x + (p.y - e.my) * qn.y;
      this._stroke.sgn = this._stroke.q0 >= 0 ? 1 : -1;
      this.beginStroke();
      this._requestDraw();
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!this._geo) return;
      if (!st) {
        if (this._dom && this._dom.plot) this._hover(ev);
        return;
      }
      if (ev.pointerId !== st.id) return;
      if (!st.moved) {
        if (Math.hypot(ev.clientX - st.cx, ev.clientY - st.cy) < DEAD_ZONE) return;
        st.moved = true;
      }
      var s = this.state, e = s.ell[st.i], p = this._toData(ev);
      var m = Math.max(s.xlim[1] - s.xlim[0], s.ylim[1] - s.ylim[0]);
      var smin = 0.005 * smaller(s.xlim, s.ylim), smax = 10 * m;
      if (st.kind === "move") {
        e.mx = clamp(p.x + st.off.x, s.xlim[0], s.xlim[1]);
        e.my = clamp(p.y + st.off.y, s.ylim[0], s.ylim[1]);
      } else if (st.kind === "major") {
        // additive: s1 follows the pointer's radial change since the grab, so
        // grabbing off the handle centre never jumps; the angle is frozen
        // while the pointer is too close to the centre to define one
        var r = Math.hypot(p.x - e.mx, p.y - e.my);
        if (r >= 0.14 * this._unit()) {
          var a = Math.atan2(p.y - e.my, p.x - e.mx), da = a - st.ang;
          st.acc += Math.atan2(Math.sin(da), Math.cos(da));
          st.ang = a;
          e.th = st.start.th + st.acc;
        }
        e.s1 = clampSd(st.start.s1 + (r - st.r0), e.s2, smin, smax);
        // autofit off: keep the dragged handle in view (reachability wins over
        // the rho ratio near the view edge)
        if (!this.ui.autofit) e.s1 = capSd(e.s1, e.mx, e.my, Math.cos(e.th), Math.sin(e.th), s, smin);
      } else {
        // signed projection on the (fixed) minor axis, relative to the grab:
        // pulling through the centre stops at the minimum, never mirrors
        var q = (p.x - e.mx) * -Math.sin(e.th) + (p.y - e.my) * Math.cos(e.th);
        e.s2 = clampSd(st.start.s2 + st.sgn * (q - st.q0), e.s1, smin, smax);
        if (!this.ui.autofit) e.s2 = capSd(e.s2, e.mx, e.my, -Math.sin(e.th), Math.cos(e.th), s, smin);
      }
      this._requestDraw();
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke:
    // commit it (growing the axes when autofit is on), then apply what was
    // queued meanwhile.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      try {
        var s = this.state;
        if (st.moved && !same(s.ell[st.i], st.start)) {
          if (this.ui.autofit && !contains(s.xlim, s.ylim, s.ell)) {
            var lim = expandTo(s.xlim, s.ylim, s.ell);
            s.xlim = lim.xlim;
            s.ylim = lim.ylim;
          }
          this.commit(s);
        } else {
          this.render();
        }
      } finally {
        this.endStroke();
      }
    },

    _hover: function (ev) {
      var hit = this._hit(this._toData(ev));
      this._dom.svg.style.cursor = !hit ? "default" : hit.kind === "move" ? "move" : "pointer";
    },

    // ---- Rendering -------------------------------------------------------------
    _build: function () {
      var self = this, d3 = root.d3;
      var svg = d3.select(this.el).append("svg");
      var dom = {
        svg: svg.node(),
        frame: svg.append("rect").attr("class", "dcr-frame")
          .attr("fill", "none").attr("stroke", "#c9ced6"),
        xAxis: svg.append("g"),
        yAxis: svg.append("g"),
        xTitle: svg.append("text").attr("text-anchor", "middle"),
        yTitle: svg.append("text").attr("text-anchor", "middle"),
        clip: svg.append("clipPath").attr("id", "dcr-bivariate-clip").append("rect"),
        plot: svg.append("g").attr("clip-path", "url(#dcr-bivariate-clip)")
          .style("pointer-events", "none"),
        message: document.createElement("div")
      };
      dom.groups = dom.plot.append("g");
      dom.axMajor = dom.plot.append("line").attr("stroke-dasharray", "3 3").attr("stroke-opacity", 0.6);
      dom.axMinor = dom.plot.append("line").attr("stroke-dasharray", "3 3").attr("stroke-opacity", 0.6);
      dom.dot = dom.plot.append("circle").attr("r", 4);
      dom.hMajor = dom.plot.append("circle").attr("r", 6).attr("fill", "#fff").attr("stroke-width", 2);
      dom.hMinor = dom.plot.append("circle").attr("r", 5).attr("fill", "#fff").attr("stroke-width", 2);
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      this.el.appendChild(dom.message);
      this._dom = dom;
      dom.svg.style.touchAction = "none";
      ["pointerdown", "pointermove"].forEach(function (t) {
        dom.svg.addEventListener(t, function (ev) {
          self[t === "pointerdown" ? "_pointerDown" : "_pointerMove"](ev);
        });
      });
      ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (t) {
        dom.svg.addEventListener(t, function (ev) { self._pointerUp(ev); });
      });
    },

    // Equal aspect: the same px per data unit on both axes, plot centred.
    _layout: function (W, H) {
      var s = this.state;
      var w = Math.max(1, W - MARGIN.left - MARGIN.right);
      var h = Math.max(1, H - MARGIN.top - MARGIN.bottom);
      var dx = s.xlim[1] - s.xlim[0], dy = s.ylim[1] - s.ylim[0];
      var k = Math.min(w / dx, h / dy);
      var pw = k * dx, ph = k * dy;
      var left = MARGIN.left + (w - pw) / 2, top = MARGIN.top + (h - ph) / 2;
      return { W: W, H: H, k: k, left: left, top: top, width: pw, height: ph };
    },

    _px: function (x, y) {
      var L = this._geo, s = this.state;
      return [L.left + (x - s.xlim[0]) * L.k, L.top + L.height - (y - s.ylim[0]) * L.k];
    },

    _toData: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, s = this.state;
      return {
        x: s.xlim[0] + (ev.clientX - r.left - L.left) / L.k,
        y: s.ylim[0] + (L.top + L.height - (ev.clientY - r.top)) / L.k
      };
    },

    // Full redraw: layout, axes and ellipses.
    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      var d3 = root.d3, dom = this._dom, s = this.state;
      var L = this._geo = this._layout(W, H);
      var x = d3.scaleLinear().domain(s.xlim).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain(s.ylim).range([L.top + L.height, L.top]);
      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.clip.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).ticks(Math.max(2, Math.round(L.width / 70))));
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xTitle.attr("x", L.left + L.width / 2).attr("y", L.top + L.height + 34)
        .text(s.names.x);
      dom.yTitle.attr("transform", "translate(" + (L.left - 38) + "," +
                      (L.top + L.height / 2) + ") rotate(-90)")
        .text(s.names.y);
      this._draw();
    },

    // Redraw the ellipses at most once per frame.
    _requestDraw: function () {
      if (!this._dom || this._frame) return;
      var self = this;
      if (typeof root.requestAnimationFrame !== "function") {
        this._draw();
        return;
      }
      this._frame = root.requestAnimationFrame(function () {
        self._frame = null;
        self._draw();
      });
    },

    // Closed path of the k-sigma contour in px.
    _contour: function (e, k) {
      var c = Math.cos(e.th), s = Math.sin(e.th), d = "";
      for (var i = 0; i <= N_ELLIPSE; i++) {
        var t = 2 * Math.PI * i / N_ELLIPSE, u = k * e.s1 * Math.cos(t), v = k * e.s2 * Math.sin(t);
        var q = this._px(e.mx + u * c - v * s, e.my + u * s + v * c);
        d += (i ? "L" : "M") + q[0].toFixed(1) + "," + q[1].toFixed(1);
      }
      return d + "Z";
    },

    // Two paths per group, built once (rebuilt when the group count or the
    // active group changes) and updated in place.
    _draw: function () {
      var dom = this._dom, L = this._geo;
      if (!dom || !dom.plot || !L) return;
      var s = this.state, act = this.activeIndex(), self = this;
      var key = s.groups.length + ":" + act;
      if (this._itemKey !== key) {
        this._itemKey = key;
        dom.groups.selectAll("*").remove();
        dom.items = [];
        // inactive groups first (faint), the active one on top
        s.groups.map(function (g, i) { return i; })
          .filter(function (i) { return i !== act; }).concat([act])
          .forEach(function (i) {
            var col = DCR.palette[i % 10], on = i === act, item = { i: i };
            item.outer = dom.groups.append("path").attr("stroke", col)
              .attr("fill", on ? col : "none").attr("fill-opacity", on ? 0.08 : null)
              .attr("stroke-width", 1.5).attr("stroke-opacity", on ? 0.5 : 0.3);
            item.inner = dom.groups.append("path").attr("fill", "none").attr("stroke", col)
              .attr("stroke-width", on ? 2.5 : 1.5).attr("stroke-opacity", on ? 1 : 0.45);
            dom.items.push(item);
          });
      }
      dom.items.forEach(function (item) {
        var e = s.ell[item.i];
        item.outer.attr("d", self._contour(e, 2));
        item.inner.attr("d", self._contour(e, 1));
      });
      var e = s.ell[act], col = DCR.palette[act % 10], h = this._handles(e);
      var c = this._px(e.mx, e.my), hm = this._px(h.major.x, h.major.y), hn = this._px(h.minor.x, h.minor.y);
      var handles = this.ui.mode === "handles" || this.ui.mode === "gestures";
      dom.dot.attr("cx", c[0]).attr("cy", c[1]).attr("fill", col);
      dom.axMajor.attr("x1", c[0]).attr("y1", c[1]).attr("x2", hm[0]).attr("y2", hm[1])
        .attr("stroke", col).style("display", handles ? null : "none");
      dom.axMinor.attr("x1", c[0]).attr("y1", c[1]).attr("x2", hn[0]).attr("y2", hn[1])
        .attr("stroke", col).style("display", handles ? null : "none");
      dom.hMajor.attr("cx", hm[0]).attr("cy", hm[1]).attr("stroke", col)
        .style("display", handles ? null : "none");
      dom.hMinor.attr("cx", hn[0]).attr("cy", hn[1]).attr("stroke", col)
        .style("display", handles ? null : "none");
    },

    _flash: function (text) {
      if (!this._dom || !this._dom.message) return;
      var msg = this._dom.message, self = this;
      msg.textContent = text;
      msg.style.display = "";
      if (this._flashTimer) root.clearTimeout(this._flashTimer);
      this._flashTimer = root.setTimeout(function () {
        msg.style.display = "none";
        self._flashTimer = null;
      }, 4000);
    }
  });

  Bivariate.toMarginal = toMarginal;
  Bivariate.fromMarginal = fromMarginal;
  Bivariate.initial = initial;
  Bivariate.fitLimits = fitLimits;
  Bivariate.contains = contains;
  Bivariate.clampSd = clampSd;
  DCR.register("bivariate", Bivariate);
})(typeof window !== "undefined" ? window : this);
