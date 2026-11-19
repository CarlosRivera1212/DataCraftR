/* Regression tool: sculpt the mean curve f(x) and the error sd s(x) of up to
 * ten groups with a soft brush, and get a random sample around the curve.
 * Undoable state (this.state, plain JSON):
 *   {groups: [names], names: {x, y, group}, xlim: [a, b], n, shared_x,
 *    f: [[K values] per group], s: [[K values >= 0] per group]}
 *   (K equally spaced points spanning xlim; f is free, ends not pinned).
 * Settings (this.ui, not undoable): {active, target: "curve" | "error",
 *   mode: "pull" | "paint", brush, level, levelPrev, lastPreset, show, ylim}.
 * brush is the Gaussian sigma as a fraction of diff(xlim), clamped to
 * [1/200, 1]. Only the active group is edited. The band is f +- 2 s. The
 * spec is raw (R/tool_regression_spec.R); the sample of "Show sample" is a
 * preview (unseeded) and never part of the spec or the history. Curves are
 * redrawn at most once per animation frame; a gesture is one stroke and one
 * history entry; the level slider is applied live and committed as one entry
 * once it rests (or before anything else happens). */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MARGIN = { top: 20, right: 16, bottom: 40, left: 56 };
  var TARGETS = ["curve", "error"];
  var MODES = ["pull", "paint"];
  var BRUSH = [0.005, 1], BRUSH_STEP = 0.005;
  var PREVIEW_PX = 26;
  var PREVIEW_MAX = 300;      // preview points per group
  var DEAD_ZONE = 3;          // px: a press that moves less than this is a click
  var LEVEL_REST = 400;       // ms: the level slider counts as released
  var PRESETS = ["const", "cone", "rcone", "bowtie", "bulge"];

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function now() {
    return root.performance && root.performance.now ? root.performance.now() : Date.now();
  }

  // Valid group names, trimmed like R's check_names(), or null.
  function cleanNames(x) {
    var out = DCR.asArray(x).map(trim);
    if (out.length < 1 || out.length > 10) return null;
    for (var i = 0; i < out.length; i++) {
      if (!out[i] || out.indexOf(out[i]) !== i) return null;
    }
    return out;
  }

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

  // Finite number (blank, boolean and arrays are not numbers), else null.
  function cleanNumber(x) {
    if (x === null || x === "" || typeof x === "boolean" || Array.isArray(x)) return null;
    var v = Number(x);
    return isFinite(v) ? v : null;
  }

  function cleanBool(x) { return typeof x === "boolean" ? x : null; }

  function cleanVarNames(x) {
    if (!x || typeof x !== "object") return null;
    var v = cleanNames([x.x, x.y, x.group].map(function (s) { return s == null ? "" : s; }));
    return v && v.length === 3 ? { x: v[0], y: v[1], group: v[2] } : null;
  }

  function clampBrush(v) { return clamp(v, BRUSH[0], BRUSH[1]); }

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

  // A finite numeric array of at least 3 values, or null.
  function cleanCurve(v) {
    if (!Array.isArray(v) || v.length < 3) return null;
    for (var i = 0; i < v.length; i++) {
      if (typeof v[i] !== "number" || !isFinite(v[i])) return null;
    }
    return v;
  }

  // Rows of curves from an option (array of arrays, or one flat array).
  function cleanRows(v) {
    if (!Array.isArray(v) || !v.length) return null;
    var rows = Array.isArray(v[0]) ? v : [v];
    var K = rows[0].length;
    for (var i = 0; i < rows.length; i++) {
      if (!cleanCurve(rows[i]) || rows[i].length !== K) return null;
    }
    return rows.map(function (r) { return r.slice(); });
  }

  // ---- Pure curve maths (exposed for tests) --------------------------------
  function grid(xlim, k) {
    var xs = [], i;
    k = k || 201;
    for (i = 0; i < k; i++) xs.push(xlim[0] + (xlim[1] - xlim[0]) * i / (k - 1));
    xs[k - 1] = xlim[1];
    return xs;
  }

  // Linear interpolation of ys (on the grid xs) at x; end values held outside.
  function interpAt(xs, ys, x) {
    var k = xs.length;
    if (!(x > xs[0])) return ys[0];
    if (x >= xs[k - 1]) return ys[k - 1];
    var u = (x - xs[0]) / (xs[k - 1] - xs[0]) * (k - 1);
    var r = Math.round(u);
    if (Math.abs(u - r) < 1e-9) return ys[r];      // exactly on a grid point
    var i = Math.min(k - 2, Math.floor(u)), f = u - i;
    return ys[i] * (1 - f) + ys[i + 1] * f;
  }

  function weight(x, x0, sigma) {
    var z = (x - x0) / sigma;
    return Math.exp(-0.5 * z * z);
  }

  // Pull: the snapshot plus dy times a Gaussian bump (centre x0) of width
  // sigma. No clamping: f is free.
  function pull(snap, xs, x0, dy, sigma) {
    var out = new Array(snap.length);
    for (var i = 0; i < snap.length; i++) out[i] = snap[i] + dy * weight(xs[i], x0, sigma);
    return out;
  }

  // Paint: one frame, in place. Each point moves towards the cursor height
  // p.y by its Gaussian weight times min(1, dt / 60) (dt in ms).
  function paint(ys, xs, p, sigma, dt) {
    var fac = Math.min(1, dt / 60);
    if (!(fac > 0) || !isFinite(p.y)) return ys;
    for (var i = 0; i < ys.length; i++) {
      ys[i] += (p.y - ys[i]) * weight(xs[i], p.x, sigma) * fac;
    }
    return ys;
  }

  // Error pull: the snapshot of s plus a Gaussian bump. dyAway is the drag of
  // the band edge (f + 2 s) away from the curve, so s moves by dyAway / 2;
  // s never goes below 0. f is accepted for symmetry with paintError.
  function pullError(snapS, f, xs, x0, dyAway, sigma) {
    var out = new Array(snapS.length);
    for (var i = 0; i < snapS.length; i++) {
      out[i] = Math.max(0, snapS[i] + dyAway / 2 * weight(xs[i], x0, sigma));
    }
    return out;
  }

  // Error paint: one frame, in place. The target is computed ONCE from the
  // distance of the cursor to the curve at the cursor x, |p.y - f(p.x)| / 2
  // (the band edge is f +- 2 s), so the band follows the curve's shape; each
  // point moves towards it by its Gaussian weight times min(1, dt / 60).
  function paintError(s, f, xs, p, sigma, dt) {
    var fac = Math.min(1, dt / 60);
    if (!(fac > 0) || !isFinite(p.y)) return s;
    var target = Math.abs(p.y - interpAt(xs, f, p.x)) / 2;
    for (var i = 0; i < s.length; i++) {
      s[i] = Math.max(0, s[i] + (target - s[i]) * weight(xs[i], p.x, sigma) * fac);
    }
    return s;
  }

  // Error shape at level L: t = (x - xmin) / diff(xlim).
  function preset(kind, xs, L) {
    var a = xs[0], d = xs[xs.length - 1] - a;
    return xs.map(function (x) {
      var t = (x - a) / d, u = Math.abs(2 * t - 1);
      switch (kind) {
        case "cone": return L * (0.1 + 0.9 * t);
        case "rcone": return L * (0.1 + 0.9 * (1 - t));
        case "bowtie": return L * (0.1 + 0.9 * u);
        case "bulge": return L * (0.1 + 0.9 * (1 - u));
      }
      return L;
    });
  }

  // Linear interpolation of one curve onto the grid of a new xlim; the end
  // values are held outside the old range.
  function resample(curve, oldXlim, newXlim) {
    var k = curve.length, xs = grid(newXlim, k), old = grid(oldXlim, k);
    return xs.map(function (x) { return interpAt(old, curve, x); });
  }

  // y limits that hold f +- 2 s of every group (f, s: one curve or an array of
  // curves), with 8 % padding.
  function fitY(f, s) {
    var F = Array.isArray(f[0]) ? f : [f], S = Array.isArray(s[0]) ? s : [s];
    var lo = Infinity, hi = -Infinity, g, i;
    for (g = 0; g < F.length; g++) {
      for (i = 0; i < F[g].length; i++) {
        lo = Math.min(lo, F[g][i] - 2 * S[g][i]);
        hi = Math.max(hi, F[g][i] + 2 * S[g][i]);
      }
    }
    if (!isFinite(lo) || !isFinite(hi)) { lo = -1; hi = 1; }
    if (hi - lo < 1e-6) { lo -= 1; hi += 1; }
    var pad = (hi - lo) * 0.08;
    return [lo - pad, hi + pad];
  }

  // Box-Muller standard normal (preview only: unseeded).
  function gauss() {
    var u = 0;
    while (u === 0) u = Math.random();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * Math.random());
  }

  function fmt(v) { return (Math.abs(v) < 1e-9 ? 0 : +v.toPrecision(4)).toString(); }

  var Regression = DCR.extend(DCR.Tool, {
    init: function (o) {
      var show = false, cb = root.document && root.document.getElementById("ctl_show");
      if (cb) show = !!cb.checked;
      else if (o.show === true) show = true;
      var level = cleanNumber(o.level);
      level = level === null || level < 0 ? 1 : level;
      this.ui = {
        active: 0,
        target: TARGETS.indexOf(o.target) >= 0 ? o.target : "curve",
        mode: MODES.indexOf(o.mode) >= 0 ? o.mode : "pull",
        brush: cleanNumber(o.brush) === null ? 0.12 : clampBrush(cleanNumber(o.brush)),
        level: level,
        levelPrev: level,
        lastPreset: null,
        show: show,
        ylim: [-1, 1]
      };
      this.level0 = level;
      this._bindDom();
    },

    initialState: function (o) {
      var groups = cleanNames(o.groups) || ["A"];
      var xlim = cleanRange(o.xlim) || [0, 10];
      var n = cleanWhole(o.n, 1, 1e6) || 200;
      if (n * groups.length > 1e6) n = Math.floor(1e6 / groups.length);
      var f0 = cleanRows(o.f), s0 = cleanRows(o.s);
      if (!f0 || !s0 || f0[0].length !== s0[0].length) {
        f0 = [grid(xlim)];
        s0 = [grid(xlim).map(function () { return 1; })];
      }
      s0 = s0.map(function (r) { return r.map(function (v) { return Math.max(0, v); }); });
      // the initial curves (options) live on the options' xlim; new groups and
      // Clear take them resampled onto the current xlim
      this._init = { xlim: xlim.slice(), f: f0, s: s0 };
      var state = {
        groups: groups,
        names: cleanVarNames(o.names) || { x: "x", y: "y", group: "group" },
        xlim: xlim,
        n: n,
        shared_x: o.shared_x === undefined ? true : o.shared_x !== false,
        f: groups.map(function (g, j) { return f0[Math.min(j, f0.length - 1)].slice(); }),
        s: groups.map(function (g, j) { return s0[Math.min(j, s0.length - 1)].slice(); })
      };
      this.ui.ylim = fitY(state.f, state.s);
      return state;
    },

    // Initial curve of group j on the grid of xlim.
    _initCurves: function (j, xlim) {
      var I = this._init, r = Math.min(j, I.f.length - 1);
      return { f: resample(I.f[r], I.xlim, xlim), s: resample(I.s[r], I.xlim, xlim) };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "regression",
        groups: s.groups.slice(),
        names: { x: s.names.x, y: s.names.y, group: s.names.group },
        xlim: s.xlim.slice(),
        f: s.f.map(function (c) { return c.map(function (v) { return isFinite(v) ? v : 0; }); }),
        s: s.s.map(function (c) { return c.map(function (v) { return v > 0 && isFinite(v) ? v : 0; }); }),
        n: s.n,
        shared_x: s.shared_x
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.groups.length - 1);
    },

    // Gaussian sigma in x units.
    _sigma: function () {
      var d = this.state.xlim[1] - this.state.xlim[0];
      return clamp(this.ui.brush * d, d / 200, d);
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
        target: { value: this.ui.target },
        mode: { value: this.ui.mode },
        brush: { value: this.ui.brush },
        level: { value: this.ui.level },
        shared_x: { value: s.shared_x },
        n: { value: s.n },
        xlim: { value: s.xlim.slice() },
        names: { value: { x: s.names.x, y: s.names.y, group: s.names.group } }
      };
    },

    // A control value in tool units, or null when invalid. Accepts both what
    // R forwards and what controls() pushes (groups as "A, B" text). The
    // equation arrives as {f: [K numbers]} evaluated by R (text is not a value).
    controlValue: function (key, value) {
      var v, s = this.state;
      switch (key) {
        case "groups":
          return cleanNames(typeof value === "string" ? value.split(",") : value);
        case "active":
          v = parseInt(value, 10) - 1;
          return v >= 0 && v < s.groups.length ? v : null;
        case "target":
          return TARGETS.indexOf(value) >= 0 ? value : null;
        case "mode":
          return MODES.indexOf(value) >= 0 ? value : null;
        case "brush":
          v = cleanNumber(value);
          return v === null ? null : clampBrush(v);
        case "level":
          v = cleanNumber(value);
          return v === null || v < 0 ? null : v;
        case "shared_x":
        case "show":
          return cleanBool(value);
        case "n":
          return cleanWhole(value, 1, 1e6);
        case "xlim":
          return cleanRange(value);
        case "names":
          return cleanVarNames(value);
        case "equation":
          if (!value || typeof value !== "object" || Array.isArray(value)) return null;
          v = cleanCurve(value.f);
          return v && v.length === s.f[0].length ? v : null;
      }
      return null;
    },

    setControl: function (key, value) {
      var s = this.state, ui = this.ui, v = this.controlValue(key, value);
      if (v === null) return;
      if (key !== "level") this._flushLevel();
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
        case "target":
        case "mode":
        case "brush":
          if (v !== ui[key]) {
            ui[key] = v;
            this._requestDraw();
          }
          break;
        case "show":
          if (v !== ui.show) {
            ui.show = v;
            this._requestDraw();
          }
          break;
        case "level":
          this._setLevel(v);
          break;
        case "shared_x":
          if (v !== s.shared_x) this._commitWith({ shared_x: v });
          break;
        case "n":
          if (v === s.n) break;
          if (this._tooMany(v, s.groups.length)) return;
          this._commitWith({ n: v });
          break;
        case "xlim":
          if (!same(v, s.xlim)) this._setXlim(v);
          break;
        case "names":
          if (!same(v, s.names)) this._commitWith({ names: v });
          break;
        case "equation":
          this._setEquation(v);
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

    _commitWith: function (patch) {
      var next = DCR.deepCopy(this.state);
      for (var k in patch) next[k] = patch[k];
      this.commit(next);
    },

    // Every commit, undo and redo refits the y axis to all groups.
    _show: function (state) {
      this.ui.ylim = fitY(state.f, state.s);
      this.ui.levelPrev = this.ui.level;
      DCR.Tool.prototype._show.call(this, state);
    },

    undo: function () {
      if (this._busy) { DCR.Tool.prototype.undo.call(this); return; }
      this._flushLevel();
      DCR.Tool.prototype.undo.call(this);
      this.ui.lastPreset = null;
    },

    redo: function () {
      if (this._busy) { DCR.Tool.prototype.redo.call(this); return; }
      this._flushLevel();
      DCR.Tool.prototype.redo.call(this);
      this.ui.lastPreset = null;
    },

    // New xlim: every curve is resampled onto the new grid, end values held
    // (one entry; the y axis refits with the commit).
    _setXlim: function (xlim) {
      var s = this.state;
      this._commitWith({
        xlim: xlim,
        f: s.f.map(function (c) { return resample(c, s.xlim, xlim); }),
        s: s.s.map(function (c) { return resample(c, s.xlim, xlim); })
      });
    },

    // The equation (already evaluated by R on the current grid) replaces f of
    // the active group: one entry, nothing when it is the same curve.
    _setEquation: function (f) {
      var i = this.activeIndex();
      if (same(f, this.state.f[i])) return;
      var next = DCR.deepCopy(this.state);
      next.f[i] = f.slice();
      this.commit(next);
    },

    // Error shape for the active group (one entry; none when s is unchanged).
    _setPreset: function (kind) {
      var next = DCR.deepCopy(this.state), i = this.activeIndex();
      next.s[i] = preset(kind, grid(next.xlim, next.s[i].length), this.ui.level);
      this.ui.lastPreset = kind;
      if (!same(next, this.state)) this.commit(next);
    },

    // The level slider is applied live to the active group's s (no history);
    // _flushLevel() commits the burst as one entry. With a remembered preset it
    // is re-applied at the new level, else the s at the start of the burst is
    // scaled by L / L_prev.
    _setLevel: function (v) {
      var ui = this.ui, s = this.state;
      if (!this._lv) {
        if (v === ui.level) return;
        var i = this.activeIndex();
        this._lv = { i: i, base: s.s[i].slice(), prev: ui.levelPrev, timer: null };
      }
      var lv = this._lv, xs = grid(s.xlim, s.s[lv.i].length);
      ui.level = v;
      if (ui.lastPreset) s.s[lv.i] = preset(ui.lastPreset, xs, v);
      else if (lv.prev > 0) s.s[lv.i] = lv.base.map(function (b) { return b * v / lv.prev; });
      else s.s[lv.i] = preset("const", xs, v);
      ui.ylim = fitY(s.f, s.s);
      this._drawAxes();
      this._requestDraw();
      if (lv.timer) root.clearTimeout(lv.timer);
      if (typeof root.setTimeout === "function") {
        var self = this;
        lv.timer = root.setTimeout(function () { self._flushLevel(); }, LEVEL_REST);
      }
    },

    _flushLevel: function () {
      var lv = this._lv;
      if (!lv) return;
      this._lv = null;
      if (lv.timer && typeof root.clearTimeout === "function") root.clearTimeout(lv.timer);
      if (same(this.state, this.history.state)) {
        this.ui.levelPrev = this.ui.level;
        return;
      }
      this.commit(this.state);
    },

    // New group list: curves keep their values by name (renames pair in
    // order); new groups start from the initial f and s.
    _setGroups: function (groups) {
      var s = this.state, map = remapGroups(s.groups, groups), self = this;
      var init = groups.map(function (g, j) { return self._initCurves(j, s.xlim); });
      var f = init.map(function (c) { return c.f; }), sd = init.map(function (c) { return c.s; });
      var gone = [];
      map.forEach(function (j, i) {
        if (j >= 0) {
          f[j] = s.f[i].slice();
          sd[j] = s.s[i].slice();
        } else {
          gone.push(s.groups[i]);
        }
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      this._smp = null;
      this._commitWith({ groups: groups, f: f, s: sd });
      if (gone.length) this._flash(gone.join(", ") + " removed \u2014 Ctrl+Z to undo");
    },

    // Clear: every group back to the initial f and s (names, range, n and
    // shared x are kept); no history entry when nothing changes.
    clear: function () {
      this._flushLevel();
      var s = this.state, self = this;
      var init = s.groups.map(function (g, j) { return self._initCurves(j, s.xlim); });
      var next = DCR.deepCopy(s);
      next.f = init.map(function (c) { return c.f; });
      next.s = init.map(function (c) { return c.s; });
      this.ui.lastPreset = null;
      this.ui.level = this.level0;
      if (!same(next, s)) this.commit(next);
      else this.syncControls();
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name), ui = this.ui;
      this._flushLevel();
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.groups.length && k !== ui.active) {
          ui.active = k;
          this.render();
          this.syncControls();
        }
      } else if (/^preset-/.test(name)) {
        var kind = name.slice(7);
        if (PRESETS.indexOf(kind) >= 0) this._setPreset(kind);
      } else if (name === "fit-y") {
        ui.ylim = fitY(this.state.f, this.state.s);
        this.render();
      } else if (name === "resample") {
        this._smp = null;
        this._requestDraw();
      } else if (name === "apply-equation") {
        this._sendEquation(null);
      } else if (name === "brush-up" || name === "brush-down") {
        // x1.2 or /1.2, kept on the slider's step so the sidebar echo is exact
        var up = name === "brush-up", f = up ? 1.2 : 1 / 1.2;
        var steps = Math.round(ui.brush * f / BRUSH_STEP);
        var cur = Math.round(ui.brush / BRUSH_STEP);
        if (steps === cur) steps += up ? 1 : -1;
        var b = clampBrush(steps * 5 / 1000);
        if (b !== ui.brush) {
          ui.brush = b;
          this._requestDraw();
          this.syncControls();
        }
      }
    },

    // ---- Sculpting: one drag = one history entry -----------------------------
    // Pointer -> {x (data, clamped to xlim), y (data, clamped to the y limits),
    // yRaw (unclamped), inside}.
    _toData: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, s = this.state;
      var yl = this.ui.ylim;
      var px = ev.clientX - r.left, py = ev.clientY - r.top;
      var t = clamp((px - L.left) / L.width, 0, 1);
      var yRaw = yl[0] + (L.top + L.height - py) / L.height * (yl[1] - yl[0]);
      return {
        x: s.xlim[0] + t * (s.xlim[1] - s.xlim[0]),
        y: clamp(yRaw, yl[0], yl[1]),
        yRaw: yRaw,
        inside: px >= L.left && px <= L.left + L.width &&
          py >= L.top && py <= L.top + L.height
      };
    },

    _pointerDown: function (ev) {
      if (ev.button !== 0 || !this._geo) return;
      if (this._stroke) {
        // a stroke whose end event never came (lost capture): finish it first
        var old = this._stroke, svg = this._dom.svg;
        var held = typeof svg.hasPointerCapture === "function" && svg.hasPointerCapture(old.id);
        if (ev.pointerId !== old.id && held) return;
        this._pointerUp({ pointerId: old.id });
      }
      this._flushLevel();
      var p = this._toData(ev);
      if (!p.inside) return;
      this._dom.svg.setPointerCapture(ev.pointerId);
      var i = this.activeIndex(), s = this.state, xs = grid(s.xlim, s.f[i].length);
      this._stroke = {
        id: ev.pointerId, i: i, target: this.ui.target, mode: this.ui.mode,
        x0: p.x, y0: p.yRaw, cx: ev.clientX, cy: ev.clientY, moved: false,
        sigma: this._sigma(), xs: xs,
        sgn: p.yRaw >= interpAt(xs, s.f[i], p.x) ? 1 : -1,   // side of the curve grabbed
        startF: s.f[i].slice(), startS: s.s[i].slice(), last: now()
      };
      this._cursor = p.x;
      this.beginStroke();
      this._requestDraw();
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!this._geo) return;
      var p = this._toData(ev);
      this._cursor = p.inside || st ? p.x : null;
      if (st && ev.pointerId === st.id && !st.moved &&
          Math.hypot(ev.clientX - st.cx, ev.clientY - st.cy) >= DEAD_ZONE) {
        st.moved = true;
        st.last = now();
      }
      if (st && ev.pointerId === st.id && st.moved) {
        var s = this.state, t = now(), dt = t - st.last;
        if (st.target === "curve") {
          if (st.mode === "pull") {
            s.f[st.i] = pull(st.startF, st.xs, st.x0, p.yRaw - st.y0, st.sigma);
          } else {
            paint(s.f[st.i], st.xs, p, this._sigma(), dt);
          }
        } else if (st.mode === "pull") {
          s.s[st.i] = pullError(st.startS, s.f[st.i], st.xs, st.x0,
                                st.sgn * (p.yRaw - st.y0), st.sigma);
        } else {
          paintError(s.s[st.i], s.f[st.i], st.xs, p, this._sigma(), dt);
        }
        st.last = t;
      }
      this._requestDraw();
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      try {
        var s = this.state;
        if (!same(s.f[st.i], st.startF) || !same(s.s[st.i], st.startS)) {
          if (!same(s.s[st.i], st.startS)) this.ui.lastPreset = null;   // a hand error edit
          this.commit(s);
        } else {
          this.render();
        }
      } finally {
        this.endStroke();
      }
    },

    // ---- Sample preview (view only: unseeded, never in the spec or history) ----
    // Per group: x (U over xlim; shared across groups when shared_x), the curve
    // value `fit`, the residual `res` and y = fit + res, from the stored
    // uniform / normal draws (so the points stay put while sculpting).
    _sampleFor: function () {
      var s = this.state, m = Math.min(s.n, PREVIEW_MAX), k = s.groups.length;
      var smp = this._smp, g, i;
      if (!smp || smp.m !== m || smp.k !== k) {
        smp = this._smp = { m: m, k: k, u: [], z: [] };
        for (g = 0; g < k; g++) {
          smp.u.push([]);
          smp.z.push([]);
          for (i = 0; i < m; i++) {
            smp.u[g].push(Math.random());
            smp.z[g].push(gauss());
          }
        }
      }
      var d = s.xlim[1] - s.xlim[0], out = [];
      for (g = 0; g < k; g++) {
        var u = s.shared_x ? smp.u[0] : smp.u[g], xs = grid(s.xlim, s.f[g].length);
        var o = { x: [], y: [], fit: [], res: [] };
        for (i = 0; i < m; i++) {
          var x = s.xlim[0] + u[i] * d, fit = interpAt(xs, s.f[g], x);
          var res = smp.z[g][i] * interpAt(xs, s.s[g], x);
          o.x.push(x);
          o.fit.push(fit);
          o.res.push(res);
          o.y.push(fit + res);
        }
        out.push(o);
      }
      return out;
    },

    // ---- Sidebar glue that only exists in a browser -----------------------------
    // Show sample is a client-side view option (R does not forward it); the
    // equation examples fill the field and send it, Enter in the field applies.
    _bindDom: function () {
      var doc = root.document, self = this;
      if (!doc || typeof doc.addEventListener !== "function") return;
      this._docListeners = [
        ["change", function (ev) {
          var t = ev.target;
          if (t && t.id === "ctl_show") self.setControl("show", !!t.checked);
        }],
        ["click", function (ev) {
          var b = ev.target && ev.target.closest ? ev.target.closest(".dcr-example") : null;
          if (b) self._sendEquation(b.getAttribute("data-equation"));
        }],
        ["keydown", function (ev) {
          if (ev.key === "Enter" && ev.target && ev.target.id === "ctl_equation") {
            self._sendEquation(ev.target.value);
          }
        }]
      ];
      this._docListeners.forEach(function (l) { doc.addEventListener(l[0], l[1]); });
    },

    // Send the equation text to R (event priority: Apply re-applies the same
    // text too; an unchanged curve is ignored by _setEquation). text null reads
    // the field. Blank text is ignored.
    _sendEquation: function (text) {
      var doc = root.document, field = doc && doc.getElementById("ctl_equation");
      if (text === null || text === undefined) text = field ? field.value : "";
      text = String(text);
      if (!/\S/.test(text)) return;
      if (field) field.value = text;
      if (root.Shiny && typeof root.Shiny.setInputValue === "function") {
        root.Shiny.setInputValue("ctl_equation", text, { priority: "event" });
      }
    },

    destroy: function () {
      var doc = root.document;
      if (doc && this._docListeners) {
        this._docListeners.forEach(function (l) { doc.removeEventListener(l[0], l[1]); });
        this._docListeners = null;
      }
      if (this._lv && this._lv.timer) root.clearTimeout(this._lv.timer);
      DCR.Tool.prototype.destroy.call(this);
    },

    // ---- Rendering -----------------------------------------------------------
    _build: function () {
      var self = this, d3 = root.d3;
      var svg = d3.select(this.el).append("svg");
      var dom = {
        svg: svg.node(),
        frame: svg.append("rect").attr("class", "dcr-frame")
          .attr("fill", "none").attr("stroke", "#c9ced6"),
        yAxis: svg.append("g"),
        xAxis: svg.append("g"),
        xTitle: svg.append("text").attr("text-anchor", "middle"),
        yTitle: svg.append("text").attr("text-anchor", "middle"),
        clip: svg.append("clipPath").attr("id", "dcr-regression-clip").append("rect"),
        plot: svg.append("g").attr("clip-path", "url(#dcr-regression-clip)")
          .style("pointer-events", "none"),
        message: document.createElement("div"),
        note: document.createElement("div"),
        mini: document.createElement("div")
      };
      dom.curves = dom.plot.append("g");
      dom.points = dom.plot.append("g");
      dom.cursorLine = dom.plot.append("line").attr("stroke", "#447099")
        .attr("stroke-opacity", 0.25).style("display", "none");
      dom.preview = dom.plot.append("path").attr("fill", "none")
        .attr("stroke", "#447099").attr("stroke-dasharray", "3 3")
        .style("display", "none");
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      dom.note.className = "dcr-regnote";
      dom.note.textContent = "Preview \u2014 Done draws a new sample";
      dom.note.style.display = "none";
      dom.mini.className = "dcr-regmini";
      dom.mini.style.display = "none";
      this.el.appendChild(dom.note);
      this.el.appendChild(dom.mini);
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
      dom.svg.addEventListener("pointerleave", function () {
        if (!self._stroke) {
          self._cursor = null;
          self._requestDraw();
        }
      });
    },

    // Full redraw: layout, axes and curves.
    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      var dom = this._dom;
      this._geo = {
        left: MARGIN.left, top: MARGIN.top,
        width: Math.max(1, W - MARGIN.left - MARGIN.right),
        height: Math.max(1, H - MARGIN.top - MARGIN.bottom)
      };
      var L = this._geo;
      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.clip.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      this._drawAxes();
      this._drawCurves();
    },

    _drawAxes: function () {
      var dom = this._dom, L = this._geo;
      if (!dom || !dom.yAxis || !L) return;
      var d3 = root.d3, s = this.state, yl = this.ui.ylim;
      var x = d3.scaleLinear().domain(s.xlim).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain(yl).range([L.top + L.height, L.top]);
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).ticks(Math.max(2, Math.round(L.width / 80))));
      dom.xTitle.attr("transform", "translate(" + (L.left + L.width / 2) + "," +
        (L.top + L.height + 32) + ")").text(s.names.x);
      dom.yTitle.attr("transform", "translate(12," + (L.top + L.height / 2) + ") rotate(-90)")
        .text(s.names.y);
    },

    // Redraw the curves and the brush preview at most once per frame.
    _requestDraw: function () {
      if (!this._dom || this._frame) return;
      var self = this;
      if (typeof root.requestAnimationFrame !== "function") {
        this._drawCurves();
        return;
      }
      this._frame = root.requestAnimationFrame(function () {
        self._frame = null;
        self._drawCurves();
      });
    },

    // Per group: band (f +- 2 s, with f +- 1 s lighter) and the curve; inactive
    // groups are faint. The elements are rebuilt only when the group count, the
    // active group or the target changes; the sample dots are one path per group.
    _drawCurves: function () {
      var dom = this._dom, L = this._geo;
      if (!dom || !dom.curves || !L) return;
      var s = this.state, ui = this.ui, act = this.activeIndex();
      var edit = ui.target === "error";
      var key = s.groups.length + ":" + act + ":" + edit;
      if (this._curveKey !== key) {
        this._curveKey = key;
        dom.curves.selectAll("*").remove();
        dom.points.selectAll("*").remove();
        dom.items = [];
        s.groups.map(function (g, i) { return i; })
          .filter(function (i) { return i !== act; }).concat([act])
          .forEach(function (i) {
            var col = DCR.palette[i % 10], on = i === act, item = { i: i, on: on };
            item.area = dom.curves.append("path").attr("fill", col)
              .attr("fill-opacity", on ? 0.13 : 0.05).attr("stroke", "none");
            if (on) {
              item.in1 = dom.curves.append("path").attr("fill", "none").attr("stroke", col)
                .attr("stroke-opacity", 0.35).attr("stroke-width", 1);
              item.in2 = dom.curves.append("path").attr("fill", "none").attr("stroke", col)
                .attr("stroke-opacity", 0.35).attr("stroke-width", 1);
              item.up = dom.curves.append("path").attr("fill", "none").attr("stroke", col)
                .attr("stroke-opacity", edit ? 0.9 : 0.4).attr("stroke-width", edit ? 2 : 1);
              item.lo = dom.curves.append("path").attr("fill", "none").attr("stroke", col)
                .attr("stroke-opacity", edit ? 0.9 : 0.4).attr("stroke-width", edit ? 2 : 1);
            }
            item.line = dom.curves.append("path").attr("fill", "none")
              .attr("stroke", col).attr("stroke-width", on ? (edit ? 2 : 3) : 1.5)
              .attr("stroke-opacity", on ? 1 : 0.45)
              .attr("stroke-dasharray", on ? null : "5 3");
            item.dots = dom.points.append("path").attr("fill", "none").attr("stroke", col)
              .attr("stroke-width", 5).attr("stroke-linecap", "round")
              .attr("stroke-opacity", on ? 0.6 : 0.35).style("display", "none");
            dom.items.push(item);
          });
      }
      var K = s.f[0].length, yl = ui.ylim, bottom = L.top + L.height, j;
      var xsPx = [];
      for (j = 0; j < K; j++) xsPx.push((L.left + j / (K - 1) * L.width).toFixed(1));
      function Y(v) { return (bottom - (v - yl[0]) / (yl[1] - yl[0]) * L.height).toFixed(1); }
      dom.items.forEach(function (item) {
        var f = s.f[item.i], sd = s.s[item.i], c, ln = "", up = "", lo = "", lorev = "", u1 = "", l1 = "";
        for (j = 0; j < K; j++) {
          c = (j ? "L" : "M") + xsPx[j] + ",";
          ln += c + Y(f[j]);
          if (item.on) {
            up += c + Y(f[j] + 2 * sd[j]);
            lo += c + Y(f[j] - 2 * sd[j]);
            u1 += c + Y(f[j] + sd[j]);
            l1 += c + Y(f[j] - sd[j]);
            lorev = "L" + xsPx[j] + "," + Y(f[j] - 2 * sd[j]) + lorev;
          } else {
            up += c + Y(f[j] + 2 * sd[j]);
            lorev = "L" + xsPx[j] + "," + Y(f[j] - 2 * sd[j]) + lorev;
          }
        }
        item.line.attr("d", ln);
        item.area.attr("d", up + lorev + "Z");
        if (item.on) {
          item.up.attr("d", up);
          item.lo.attr("d", lo);
          item.in1.attr("d", u1);
          item.in2.attr("d", l1);
        }
      });

      // sample preview and the residual mini plot
      var smp = null;
      if (ui.show) {
        smp = this._sampleFor();
        dom.items.forEach(function (item) {
          var o = smp[item.i], d = "";
          for (j = 0; j < o.x.length; j++) {
            d += "M" + (L.left + (o.x[j] - s.xlim[0]) / (s.xlim[1] - s.xlim[0]) * L.width).toFixed(1) +
              "," + Y(o.y[j]) + "h0.01";
          }
          item.dots.attr("d", d).style("display", null);
        });
      } else {
        dom.items.forEach(function (item) { item.dots.style("display", "none"); });
      }
      this._drawMini(smp ? smp[act] : null);

      // brush preview: the Gaussian falloff under the cursor
      if (this._cursor === null || this._cursor === undefined) {
        dom.preview.style("display", "none");
        dom.cursorLine.style("display", "none");
        return;
      }
      var sigma = this._sigma(), c0 = this._cursor, pd = "", xs = grid(s.xlim, K);
      for (j = 0; j < K; j++) {
        var w = weight(xs[j], c0, sigma);
        if (w > 0.01) pd += (pd ? "L" : "M") + xsPx[j] + "," + (bottom - w * PREVIEW_PX).toFixed(1);
      }
      var cx = L.left + (c0 - s.xlim[0]) / (s.xlim[1] - s.xlim[0]) * L.width;
      dom.preview.attr("d", pd || null).style("display", pd ? null : "none");
      dom.cursorLine.attr("x1", cx).attr("x2", cx).attr("y1", L.top).attr("y2", bottom)
        .style("display", null);
    },

    // Residual-vs-fitted plot of the active group's preview (inline styles:
    // the stylesheet's `.dcr-tool svg text` rule would override attributes).
    _drawMini: function (o) {
      var dom = this._dom;
      dom.note.style.display = o ? "" : "none";
      dom.mini.style.display = o ? "" : "none";
      if (!o) return;
      var w = 210, h = 130, ml = 38, mb = 20, mt = 16, mr = 8, i;
      var flo = Infinity, fhi = -Infinity, rm = 1e-9;
      for (i = 0; i < o.fit.length; i++) {
        flo = Math.min(flo, o.fit[i]);
        fhi = Math.max(fhi, o.fit[i]);
        rm = Math.max(rm, Math.abs(o.res[i]));
      }
      if (!(fhi - flo > 1e-9)) { flo -= 1; fhi += 1; }
      rm *= 1.1;
      function px(v) { return ml + (v - flo) / (fhi - flo) * (w - ml - mr); }
      function py(v) { return mt + (1 - (v + rm) / (2 * rm)) * (h - mt - mb); }
      var txt = "font-size:10px;fill:#6b7785;";
      var col = DCR.palette[this.activeIndex() % 10];
      var dots = "";
      for (i = 0; i < o.fit.length; i++) {
        dots += "M" + px(o.fit[i]).toFixed(1) + "," + py(o.res[i]).toFixed(1) + "h0.01";
      }
      var g = this.state.groups[this.activeIndex()];
      var title = "Residuals vs fitted" + (this.state.groups.length > 1 ? " (" + g + ")" : "");
      var svg = "<svg width=\"" + w + "\" height=\"" + h + "\" viewBox=\"0 0 " + w + " " + h + "\">" +
        "<text x=\"" + ml + "\" y=\"11\" style=\"" + txt + "fill:#1f2933;font-weight:600\"></text>" +
        "<line x1=\"" + ml + "\" x2=\"" + (w - mr) + "\" y1=\"" + py(0) + "\" y2=\"" + py(0) +
        "\" stroke=\"#c9ced6\"/>" +
        "<text x=\"" + (ml - 4) + "\" y=\"" + (py(rm) + 9) + "\" text-anchor=\"end\" style=\"" + txt + "\">" + fmt(rm) + "</text>" +
        "<text x=\"" + (ml - 4) + "\" y=\"" + py(-rm) + "\" text-anchor=\"end\" style=\"" + txt + "\">" + fmt(-rm) + "</text>" +
        "<text x=\"" + ml + "\" y=\"" + (h - 5) + "\" style=\"" + txt + "\">" + fmt(flo) + "</text>" +
        "<text x=\"" + (w - mr) + "\" y=\"" + (h - 5) + "\" text-anchor=\"end\" style=\"" + txt + "\">" + fmt(fhi) + "</text>" +
        "<path d=\"" + dots + "\" fill=\"none\" stroke=\"" + col + "\" stroke-width=\"4\" " +
        "stroke-linecap=\"round\" stroke-opacity=\"0.55\"/></svg>";
      dom.mini.innerHTML = svg;
      // the title is user text (group name): set as text, never as markup
      var t = dom.mini.querySelector("text");
      if (t) t.textContent = title;
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

  Regression.pull = pull;
  Regression.paint = paint;
  Regression.pullError = pullError;
  Regression.paintError = paintError;
  Regression.preset = preset;
  Regression.resample = resample;
  Regression.fitY = fitY;
  Regression.grid = grid;
  DCR.register("regression", Regression);
})(typeof window !== "undefined" ? window : this);
