/* Radar tool: draw a mean profile and a spread (sd) per variable for up to ten
 * groups on a radar chart, and get a random sample (independent normals per
 * variable, truncated to the variable's range).
 * Undoable state (this.state, plain JSON):
 *   {groups: [names], variables: [names], ranges: [[min, max] per variable],
 *    mean: [[per variable] per group], sd: [[per variable] per group],
 *    n, integers, group_name}
 * Settings (this.ui, not undoable): {active, target: "mean" | "spread", show}.
 * The handles are the location and scale of the normal BEFORE truncation; the
 * band is clipped at the range ends and the tooltip adds "(actual ...)" when
 * the truncated moments differ noticeably. Spokes are evenly spaced, the first
 * at the top, clockwise. A drag is one stroke and one history entry, relative
 * to the press (no jump); a press that moves less than 3 px adds nothing.
 * The preview of "Show sample" is illustrative (unseeded rejection sampler)
 * and never part of the spec or the history. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var TARGETS = ["mean", "spread"];
  var DEAD_ZONE = 3;          // px: a press that moves less than this is a click
  var PREVIEW_MAX = 300;      // polylines per group
  var HIT_POINT = 13, HIT_EDGE = 8, HIT_MERGE = 4;   // px
  var RINGS = 5;
  var SD_FRAC = 0.1;
  var DEFAULT_RANGE = [0, 10];

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function fmt(v) { return (Math.abs(v) < 1e-9 ? 0 : +v.toPrecision(3)).toString(); }

  // Valid names, trimmed like R's check_names(), between lo and hi, or null.
  function cleanNames(x, lo, hi) {
    var out = DCR.asArray(typeof x === "string" ? x.split(",") : x).map(trim);
    if (out.length < lo || out.length > hi) return null;
    for (var i = 0; i < out.length; i++) {
      if (!out[i] || out.indexOf(out[i]) !== i) return null;
    }
    return out;
  }

  function cleanWhole(x, lo, hi) {
    var v = Array.isArray(x) ? NaN : Number(x);
    return x !== null && x !== "" && typeof x !== "boolean" && isFinite(v) &&
      v === Math.round(v) && v >= lo && v <= hi ? v : null;
  }

  function cleanNumber(x) {
    if (x === null || x === undefined || x === "" || typeof x === "boolean" || Array.isArray(x)) return null;
    var v = Number(x);
    return isFinite(v) ? v : null;
  }

  function cleanBool(x) { return typeof x === "boolean" ? x : null; }

  // Ranges as nested pairs from either form (flat 2p array from the fields
  // binding, or pairs from R); null unless p valid increasing pairs.
  function cleanRanges(x, p) {
    var a = DCR.asArray(x), pairs = [], i, flat;
    if (a.length && Array.isArray(a[0])) {
      pairs = a.map(function (r) { return DCR.asArray(r); });
    } else {
      if (a.length % 2) return null;
      for (i = 0; i < a.length; i += 2) pairs.push([a[i], a[i + 1]]);
    }
    if (pairs.length !== p) return null;
    flat = [];
    for (i = 0; i < pairs.length; i++) {
      if (pairs[i].length !== 2) return null;
      var lo = cleanNumber(pairs[i][0]), hi = cleanNumber(pairs[i][1]);
      if (lo === null || hi === null || !(lo < hi)) return null;
      flat.push([lo, hi]);
    }
    return flat;
  }

  // k x p numeric rows from a nested or (one group) flat option, or null.
  function cleanRows(v, k, p) {
    if (!Array.isArray(v) || !v.length) return null;
    var rows = Array.isArray(v[0]) ? v : (k === 1 ? [v] : null);
    if (!rows || rows.length !== k) return null;
    for (var i = 0; i < k; i++) {
      if (!Array.isArray(rows[i]) || rows[i].length !== p) return null;
      for (var j = 0; j < p; j++) {
        if (typeof rows[i][j] !== "number" || !isFinite(rows[i][j])) return null;
      }
    }
    return rows.map(function (r) { return r.slice(); });
  }

  // Map old indices to new ones: names present in both are kept; with the
  // same number of names the rest are renames (paired in order).
  function remap(oldNames, newNames) {
    var map = oldNames.map(function (g) { return newNames.indexOf(g); });
    if (oldNames.length === newNames.length) {
      var free = newNames.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  // ---- Pure maths (exposed for tests) ----------------------------------------
  // erf: Taylor series for |x| < 3, continued fraction of erfc beyond (about
  // 1e-15 absolute).
  function erf(x) {
    var ax = Math.abs(x), r, term, sum, n, t, k;
    if (ax < 3) {
      term = ax;
      sum = ax;
      for (n = 1; n < 100; n++) {
        term *= -ax * ax / n;
        sum += term / (2 * n + 1);
        if (Math.abs(term) < 1e-18) break;
      }
      r = 2 / Math.sqrt(Math.PI) * sum;
    } else {
      t = ax;
      for (k = 60; k >= 1; k--) t = ax + (k / 2) / t;
      r = 1 - Math.exp(-ax * ax) / (Math.sqrt(Math.PI) * t);
    }
    return x < 0 ? -r : r;
  }
  function pdf(z) { return Math.exp(-0.5 * z * z) / Math.sqrt(2 * Math.PI); }
  function cdf(z) { return 0.5 * (1 + erf(z / Math.SQRT2)); }

  // Exact mean and sd of a normal(mean, sd) truncated to [a, b] (same rules
  // as R's tnorm_moments(): uniform moments when sd is huge for the range).
  // The degenerate branches below are unreachable with in-range means (R flips
  // such cases instead).
  function tnormMoments(mean, sd, a, b) {
    if (!(sd > 0)) return { mean: mean, sd: 0 };
    var za = (a - mean) / sd, zb = (b - mean) / sd;
    if (zb - za < 1e-3) return { mean: (a + b) / 2, sd: (b - a) / Math.sqrt(12) };
    var z = cdf(zb) - cdf(za), m, v;
    if (!(z > 1e-300)) return { mean: clamp(mean, a, b), sd: 0 };
    m = (pdf(za) - pdf(zb)) / z;
    v = 1 + (za * pdf(za) - zb * pdf(zb)) / z - m * m;
    if (!isFinite(m) || !isFinite(v)) return { mean: clamp(mean, a, b), sd: 0 };
    m = clamp(m, za, zb);
    return { mean: mean + sd * m, sd: sd * Math.min(Math.sqrt(Math.max(v, 0)), (zb - za) / 2) };
  }

  // Initial profiles (same rule as R's radar_initial()): group i, variable j
  // of p, K groups: mean = mid + 0.25 * width * cos(2 pi j / p + 2 pi i / max(2, K)),
  // sd = 10 % of the range. `groups` is a count or an array of names.
  function initial(groups, ranges) {
    var K = typeof groups === "number" ? groups : groups.length, p = ranges.length;
    var mean = [], sd = [], i, j;
    for (i = 0; i < K; i++) {
      mean.push([]);
      sd.push([]);
      for (j = 0; j < p; j++) {
        var w = ranges[j][1] - ranges[j][0], mid = (ranges[j][0] + ranges[j][1]) / 2;
        var ang = 2 * Math.PI * j / p + 2 * Math.PI * i / Math.max(2, K);
        mean[i].push(mid + 0.25 * w * Math.cos(ang));
        sd[i].push(SD_FRAC * w);
      }
    }
    return { mean: mean, sd: sd };
  }

  // Means (one value or an array) from one range onto another, proportionally.
  function rescale(values, oldRange, newRange) {
    var ow = oldRange[1] - oldRange[0], nw = newRange[1] - newRange[0];
    function one(v) { return clamp(newRange[0] + (v - oldRange[0]) / ow * nw, newRange[0], newRange[1]); }
    return Array.isArray(values) ? values.map(one) : one(values);
  }

  // Spreads rescale by the width ratio only.
  function rescaleSpread(values, oldRange, newRange) {
    var ow = oldRange[1] - oldRange[0], nw = newRange[1] - newRange[0];
    function one(v) { return clamp(v * nw / ow, 0, nw / 2); }
    return Array.isArray(values) ? values.map(one) : one(values);
  }

  // Component of the vector p = [dx, dy] along a spoke at angle `ang`.
  function project(p, ang) { return p[0] * Math.cos(ang) + p[1] * Math.sin(ang); }

  // Spoke k of p: first at the top, clockwise.
  function spokeAngle(k, p) { return -Math.PI / 2 + 2 * Math.PI * k / p; }

  // Distance from point q to the segment a-b.
  function segDist(q, a, b) {
    var dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy;
    var t = l2 ? clamp(((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / l2, 0, 1) : 0;
    return Math.hypot(q[0] - (a[0] + t * dx), q[1] - (a[1] + t * dy));
  }

  function gauss(rnd) {
    var u = 0;
    while (u === 0) u = rnd();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rnd());
  }

  // Seeded stream (mulberry32) for the preview.
  function stream(seed) {
    return function () {
      seed = (seed + 0x6D2B79F5) | 0;
      var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // One preview value: normal(mean, sd) by rejection into [a, b] (50 tries,
  // then clamped); integers rounds and clamps.
  function previewValue(rnd, mean, sd, a, b, ints) {
    var v = mean, t;
    if (sd > 0) {
      for (t = 0; t < 50; t++) {
        v = mean + sd * gauss(rnd);
        if (v >= a && v <= b) break;
      }
    }
    v = clamp(v, a, b);
    return ints ? clamp(Math.round(v), a, b) : v;
  }

  var Radar = DCR.extend(DCR.Tool, {
    init: function (o) {
      var show = false, cb = root.document && root.document.getElementById &&
        root.document.getElementById("ctl_show");
      if (cb) show = !!cb.checked;
      else if (o.show === true) show = true;
      this.ui = {
        active: 0,
        target: TARGETS.indexOf(o.target) >= 0 ? o.target : "mean",
        show: show
      };
      this._salt = (Math.random() * 1e9) | 0;
      this._cache = {};
      this._bindDom();
    },

    initialState: function (o) {
      var groups = cleanNames(o.groups, 1, 10) || ["A", "B"];
      var vars = cleanNames(o.variables, 3, 12) || ["V1", "V2", "V3", "V4", "V5"];
      var p = vars.length, k = groups.length;
      var ranges = cleanRanges(o.ranges, p);
      if (!ranges) ranges = vars.map(function () { return DEFAULT_RANGE.slice(); });
      var init = initial(groups, ranges);
      var mean = cleanRows(o.mean, k, p) || init.mean;
      var sd = cleanRows(o.sd, k, p) || init.sd;
      mean = mean.map(function (row) {
        return row.map(function (v, j) { return clamp(v, ranges[j][0], ranges[j][1]); });
      });
      sd = sd.map(function (row) {
        return row.map(function (v, j) { return clamp(v, 0, (ranges[j][1] - ranges[j][0]) / 2); });
      });
      var n = cleanWhole(o.n, 1, 1e6) || 50;
      if (n * k > 1e6) n = Math.floor(1e6 / k);
      var gname = typeof o.group_name === "string" ? trim(o.group_name) : "group";
      if (!gname || vars.indexOf(gname) >= 0) gname = "group";
      this._rangesStamp = JSON.stringify(vars);
      return {
        groups: groups, variables: vars, ranges: ranges, mean: mean, sd: sd,
        n: n, integers: o.integers === true, group_name: gname
      };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "radar",
        groups: s.groups.slice(),
        variables: s.variables.slice(),
        ranges: s.ranges.map(function (r) { return r.slice(); }),
        mean: s.mean.map(function (r) { return r.slice(); }),
        sd: s.sd.map(function (r) { return r.map(function (v) { return v > 0 ? v : 0; }); }),
        n: s.n,
        integers: s.integers,
        group_name: s.group_name
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.groups.length - 1);
    },

    controls: function () {
      var s = this.state, flat = [];
      s.ranges.forEach(function (r) { flat.push(r[0], r[1]); });
      return {
        groups: { value: s.groups.join(", ") },
        active: {
          choices: s.groups.map(function (g, i) {
            return { value: String(i + 1), label: g, color: DCR.palette[i % 10] };
          }),
          value: String(this.activeIndex() + 1)
        },
        target: { value: this.ui.target },
        variables: { value: s.variables.join(", ") },
        ranges: { value: flat },
        n: { value: s.n },
        integers: { value: s.integers },
        group_name: { value: s.group_name }
      };
    },

    // A control value in tool units, or null when invalid. Accepts what R
    // forwards (name vectors, pairs) and what controls() pushes (text, flat).
    controlValue: function (key, value) {
      var v, s = this.state;
      switch (key) {
        case "groups": return cleanNames(value, 1, 10);
        case "variables": return cleanNames(value, 3, 12);
        case "active":
          v = parseInt(value, 10) - 1;
          return v >= 0 && v < s.groups.length ? v : null;
        case "target": return TARGETS.indexOf(value) >= 0 ? value : null;
        case "ranges": return cleanRanges(value, s.variables.length);
        case "n": return cleanWhole(value, 1, 1e6);
        case "integers":
        case "show": return cleanBool(value);
        case "group_name":
          v = cleanNames(value, 1, 1);
          return v ? v[0] : null;
      }
      return null;
    },

    // Done flush: ranges first, so pairs map to the old variable names even
    // when the variable count changes in the same flush.
    flushControls: function (values) {
      var self = this, vals = values || {}, keys = Object.keys(vals);
      keys.sort(function (a, b) { return (a === "ranges" ? 0 : 1) - (b === "ranges" ? 0 : 1); });
      keys.forEach(function (key) {
        try {
          if (self.controlValue(key, vals[key]) !== null) self.setControl(key, vals[key]);
        } catch (e) { /* ignored: Done must still send the spec */ }
      });
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
        case "variables":
          if (same(v, s.variables)) break;
          if (v.indexOf(s.group_name) >= 0) {
            this._flash("Variable names must differ from the group column name");
            this.syncControls();
            return;
          }
          this._setVariables(v);
          break;
        case "active":
          if (v !== ui.active) {
            ui.active = v;
            this._hover = null;
            this.render();
          }
          this.syncControls();
          break;
        case "target":
          if (v !== ui.target) {
            ui.target = v;
            this._hover = null;
            this._requestDraw();
          }
          break;
        case "show":
          if (v !== ui.show) {
            ui.show = v;
            this._requestDraw();
          }
          break;
        case "ranges":
          this._setRanges(v);
          break;
        case "n":
          if (v === s.n) break;
          if (this._tooMany(v, s.groups.length)) return;
          this._commitWith({ n: v });
          break;
        case "integers":
          if (v !== s.integers) this._commitWith({ integers: v });
          break;
        case "group_name":
          if (v === s.group_name) break;
          if (s.variables.indexOf(v) >= 0) {
            this._flash("The group column name must differ from the variable names");
            this.syncControls();
            return;
          }
          this._commitWith({ group_name: v });
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

    // A new range for a variable rescales its means and sds in every group
    // (the polygon keeps its shape): one entry.
    _setRanges: function (ranges) {
      var s = this.state, next = DCR.deepCopy(s), changed = false;
      ranges.forEach(function (r, j) {
        if (same(r, s.ranges[j])) return;
        changed = true;
        for (var g = 0; g < s.groups.length; g++) {
          next.mean[g][j] = rescale(s.mean[g][j], s.ranges[j], r);
          next.sd[g][j] = rescaleSpread(s.sd[g][j], s.ranges[j], r);
        }
        next.ranges[j] = r.slice();
      });
      if (changed) this.commit(next);
    },

    // New group list: profiles keep their values by name (renames pair in
    // order); a new group starts from the initial profile of its position.
    _setGroups: function (groups) {
      var s = this.state, map = remap(s.groups, groups), gone = [];
      var init = initial(groups, s.ranges), mean = init.mean, sd = init.sd;
      map.forEach(function (j, i) {
        if (j >= 0) {
          mean[j] = s.mean[i].slice();
          sd[j] = s.sd[i].slice();
        } else {
          gone.push(s.groups[i]);
        }
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      this._commitWith({ groups: groups, mean: mean, sd: sd });
      if (gone.length) this._flash(gone.join(", ") + " removed " + String.fromCharCode(8212) + " Ctrl+Z to undo");
    },

    // New variable list: columns keep their values by name (renames pair in
    // order); a new variable takes the first variable's range, means at the
    // midpoint and sd 10 % of its range.
    _setVariables: function (vars) {
      var s = this.state, map = remap(s.variables, vars), gone = [];
      var r0 = s.ranges[0];
      var ranges = vars.map(function () { return r0.slice(); });
      var mid = (r0[0] + r0[1]) / 2, w = r0[1] - r0[0];
      var mean = s.groups.map(function () { return vars.map(function () { return mid; }); });
      var sd = s.groups.map(function () { return vars.map(function () { return SD_FRAC * w; }); });
      map.forEach(function (j, i) {
        if (j < 0) {
          gone.push(s.variables[i]);
          return;
        }
        ranges[j] = s.ranges[i].slice();
        for (var g = 0; g < s.groups.length; g++) {
          mean[g][j] = s.mean[g][i];
          sd[g][j] = s.sd[g][i];
        }
      });
      this._cache = {};
      this._commitWith({ variables: vars, ranges: ranges, mean: mean, sd: sd });
      if (gone.length) this._flash(gone.join(", ") + " removed " + String.fromCharCode(8212) + " Ctrl+Z to undo");
    },

    // Clear: every group back to the initial profile for the current groups,
    // variables and ranges (names, ranges and n are kept); one entry, none
    // when nothing changes.
    clear: function () {
      var s = this.state, init = initial(s.groups, s.ranges);
      var next = DCR.deepCopy(s);
      next.mean = init.mean;
      next.sd = init.sd;
      if (!same(next, s)) this.commit(next);
    },

    // Spread preset: sd = f x range of every variable, active group (one entry).
    _setSpread: function (f) {
      var s = this.state, i = this.activeIndex(), next = DCR.deepCopy(s);
      next.sd[i] = s.ranges.map(function (r) { return f * (r[1] - r[0]); });
      if (!same(next, s)) this.commit(next);
    },

    // Copy the active group's sds to every group (one entry).
    _sameAll: function () {
      var s = this.state, i = this.activeIndex(), next = DCR.deepCopy(s);
      next.sd = s.groups.map(function () { return s.sd[i].slice(); });
      if (!same(next, s)) this.commit(next);
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name), ui = this.ui;
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.groups.length && k !== ui.active) {
          ui.active = k;
          this._hover = null;
          this.render();
          this.syncControls();
        }
      } else if (name === "preset-tight") this._setSpread(0.05);
      else if (name === "preset-medium") this._setSpread(0.1);
      else if (name === "preset-wide") this._setSpread(0.2);
      else if (name === "same-all") this._sameAll();
      else if (name === "resample") {
        this._salt = (Math.random() * 1e9) | 0;
        this._cache = {};
        this._requestDraw();
      }
    },

    // The ranges fields follow the variable list: rebuilt (children only,
    // the container stays) whenever the names change, then R re-validates.
    syncControls: function () {
      this._syncRanges();
      DCR.Tool.prototype.syncControls.call(this);
    },

    _syncRanges: function () {
      var doc = root.document, s = this.state;
      var el = doc && typeof doc.getElementById === "function" ? doc.getElementById("ctl_ranges") : null;
      if (!el || typeof doc.createElement !== "function") return;
      var stamp = JSON.stringify(s.variables);
      if (this._rangesStamp === stamp && el.querySelectorAll("input").length === 2 * s.variables.length) return;
      this._rangesStamp = stamp;
      el.textContent = "";
      s.variables.forEach(function (name, j) {
        var row = doc.createElement("div"), label = doc.createElement("span");
        row.className = "dcr-range-row";
        label.className = "dcr-range-name";
        label.textContent = name;
        row.appendChild(label);
        [["min", 0], ["max", 1]].forEach(function (w) {
          var inp = doc.createElement("input");
          inp.type = "number";
          inp.className = "form-control";
          inp.step = "any";
          inp.value = String(s.ranges[j][w[1]]);
          inp.setAttribute("aria-label", name + " " + w[0]);
          row.appendChild(inp);
        });
        el.appendChild(row);
      });
      if (typeof root.Event === "function") el.dispatchEvent(new root.Event("change", { bubbles: true }));
    },

    // ---- Geometry and hit testing --------------------------------------------
    _ang: function (k) { return spokeAngle(k, this.state.variables.length); },

    _range: function (k) { return this.state.ranges[k][1] - this.state.ranges[k][0]; },

    // Point on spoke k at fraction f of its range (0 centre, 1 rim).
    _pt: function (k, f) {
      var L = this._geo, a = this._ang(k);
      return [L.cx + L.R * f * Math.cos(a), L.cy + L.R * f * Math.sin(a)];
    },

    _frac: function (k, v) { return (v - this.state.ranges[k][0]) / this._range(k); },

    _meanPt: function (g, k) { return this._pt(k, this._frac(k, this.state.mean[g][k])); },

    // Band handles, clipped at the range ends.
    _outPt: function (g, k) {
      var s = this.state;
      return this._pt(k, clamp(this._frac(k, s.mean[g][k] + s.sd[g][k]), 0, 1));
    },

    _inPt: function (g, k) {
      var s = this.state;
      return this._pt(k, clamp(this._frac(k, s.mean[g][k] - s.sd[g][k]), 0, 1));
    },

    // Pointer in the element's own pixels.
    _pos: function (ev) {
      var r = this.el.getBoundingClientRect();
      return [ev.clientX - r.left, ev.clientY - r.top];
    },

    _hit: function (q) {
      var s = this.state, ag = this.activeIndex(), p = s.variables.length;
      var best = null, bd, k, d;
      if (this.ui.target === "mean") {
        bd = HIT_POINT;
        for (k = 0; k < p; k++) {
          var m = this._meanPt(ag, k);
          d = Math.hypot(q[0] - m[0], q[1] - m[1]);
          if (d < bd) { bd = d; best = { type: "vertex", k: k }; }
        }
        if (best) return best;
        bd = HIT_EDGE;
        for (k = 0; k < p; k++) {
          d = segDist(q, this._meanPt(ag, k), this._meanPt(ag, (k + 1) % p));
          if (d < bd) { bd = d; best = { type: "edge", k: k }; }
        }
        if (best) return best;
      } else {
        bd = HIT_POINT;
        for (k = 0; k < p; k++) {
          var mq = this._meanPt(ag, k), oq = this._outPt(ag, k), iq = this._inPt(ag, k);
          var dm = Math.hypot(q[0] - mq[0], q[1] - mq[1]);
          var dO = Math.hypot(q[0] - oq[0], q[1] - oq[1]), dI = Math.hypot(q[0] - iq[0], q[1] - iq[1]);
          // coincident handles (sd about 0): the first movement picks one
          if (Math.hypot(oq[0] - iq[0], oq[1] - iq[1]) < HIT_MERGE) {
            if (dm < bd) { bd = dm; best = { type: "sd", k: k, sign: 0 }; }
            continue;
          }
          if (dO < bd) { bd = dO; best = { type: "sd", k: k, sign: 1 }; }
          if (dI < bd) { bd = dI; best = { type: "sd", k: k, sign: -1 }; }
        }
        if (best) return best;
      }
      bd = HIT_EDGE;
      for (var g = 0; g < s.groups.length; g++) {
        if (g === ag) continue;
        for (k = 0; k < p; k++) {
          d = segDist(q, this._meanPt(g, k), this._meanPt(g, (k + 1) % p));
          if (d < bd) { bd = d; best = { type: "group", g: g }; }
        }
      }
      return best;
    },

    // ---- Dragging: one drag = one history entry --------------------------------
    _pointerDown: function (ev) {
      if (ev.button !== 0 || !this._geo) return;
      if (this._stroke) {
        // a stroke whose end event never came (lost capture): finish it first
        var old = this._stroke, svg = this._dom && this._dom.svg;
        var held = svg && typeof svg.hasPointerCapture === "function" && svg.hasPointerCapture(old.id);
        if (ev.pointerId !== old.id && held) return;
        this._pointerUp({ pointerId: old.id });
      }
      if (typeof ev.preventDefault === "function") ev.preventDefault();
      var q = this._pos(ev), h = this._hit(q);
      if (!h) return;
      if (h.type === "group") {
        if (h.g !== this.ui.active) {
          this.ui.active = h.g;
          this._hover = null;
          this.render();
          this.syncControls();
        }
        return;
      }
      try { this._dom.svg.setPointerCapture(ev.pointerId); } catch (e) { /* no capture */ }
      var i = this.activeIndex(), s = this.state;
      this._stroke = {
        id: ev.pointerId, type: h.type, k: h.k, sign: h.sign || 0, i: i,
        cx: ev.clientX, cy: ev.clientY, px: q[0], py: q[1], moved: false,
        m0: s.mean[i].slice(), s0: s.sd[i].slice()
      };
      this.beginStroke();
      this._requestDraw();
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!this._geo) return;
      if (st && ev.pointerId === st.id) {
        // a mouse move with no button held: the release was lost
        if (ev.pointerType === "mouse" && ev.buttons === 0) {
          this._pointerUp({ pointerId: st.id });
          return;
        }
        var q = this._pos(ev), dx = ev.clientX - st.cx, dy = ev.clientY - st.cy;
        st.px = q[0];
        st.py = q[1];
        if (!st.moved) {
          if (Math.hypot(dx, dy) < DEAD_ZONE) { this._requestDraw(); return; }
          st.moved = true;
        }
        this._applyDrag(st, dx, dy);
      } else if (!st) {
        var h = this._hit(this._pos(ev));
        this._hover = h && h.type !== "group" ? h : null;
        var svg = this._dom && this._dom.svg;
        if (svg) {
          svg.style.cursor = !h ? "default" : h.type === "group" ? "pointer" :
            h.type === "vertex" ? "grab" : h.type === "edge" ? "move" : "ew-resize";
        }
      }
      this._requestDraw();
    },

    // Everything relative to the press (dx, dy in px since the press).
    _applyDrag: function (st, dx, dy) {
      var s = this.state, i = st.i, k = st.k, p = s.variables.length, k2, d, w, lo, hi, px;
      var R = this._geo.R, v = [dx, dy];
      function move(j) {
        w = s.ranges[j][1] - s.ranges[j][0];
        lo = s.ranges[j][0];
        hi = s.ranges[j][1];
        s.mean[i][j] = clamp(st.m0[j] + project(v, spokeAngle(j, p)) / R * w, lo, hi);
      }
      if (st.type === "vertex") move(k);
      else if (st.type === "edge") {
        k2 = (k + 1) % p;
        move(k);
        move(k2);
      } else {
        w = s.ranges[k][1] - s.ranges[k][0];
        px = project(v, spokeAngle(k, p));
        d = px / R * w;
        if (st.sign === 0 && Math.abs(px) >= 2) st.sign = px > 0 ? 1 : -1;   // first real movement picks
        s.sd[i][k] = clamp(st.s0[k] + st.sign * d, 0, w / 2);
      }
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      try {
        var s = this.state;
        if (!same(s.mean[st.i], st.m0) || !same(s.sd[st.i], st.s0)) this.commit(s);
        else this.render();
      } finally {
        this.endStroke();
      }
    },

    // ---- Tooltip text ------------------------------------------------------------
    // "variable: mean +- sd", plus "(actual m +- s)" when the truncated moments
    // differ from the drawn ones by more than 1 % of the range.
    _tipText: function (g, k) {
      var s = this.state, a = s.ranges[k][0], b = s.ranges[k][1], w = b - a;
      var m = s.mean[g][k], sd = s.sd[g][k], t = tnormMoments(m, sd, a, b);
      var txt = s.variables[k] + ": " + fmt(m) + " +- " + fmt(sd);
      if (Math.abs(t.mean - m) > 0.01 * w || Math.abs(t.sd - sd) > 0.01 * w) {
        txt += " (actual " + fmt(t.mean) + " +- " + fmt(t.sd) + ")";
      }
      return txt;
    },

    // ---- Preview (view only: unseeded, never in the spec or history) -----------
    // Values of variable k of group g for the first m individuals; recomputed
    // only when that profile changes.
    _previewVals: function (g, k, m) {
      var s = this.state, a = s.ranges[k][0], b = s.ranges[k][1];
      var key = [s.mean[g][k], s.sd[g][k], a, b, s.integers, m, this._salt].join("|");
      var c = this._cache[g + ":" + k];
      if (c && c.key === key) return c.vals;
      var rnd = stream(this._salt + g * 7919 + k * 1299709), vals = [];
      for (var i = 0; i < m; i++) vals.push(previewValue(rnd, s.mean[g][k], s.sd[g][k], a, b, s.integers));
      this._cache[g + ":" + k] = { key: key, vals: vals };
      return vals;
    },

    // ---- Sidebar glue that only exists in a browser ------------------------------
    // Show sample is a client-side view option (R does not forward it); an
    // invalid edit of the range fields puts the state's values back.
    _bindDom: function () {
      var doc = root.document, self = this;
      if (!doc || typeof doc.addEventListener !== "function") return;
      this._docListeners = [
        ["change", function (ev) {
          var t = ev.target;
          if (!t) return;
          if (t.id === "ctl_show") self.setControl("show", !!t.checked);
          else if (typeof t.closest === "function" && t.closest("#ctl_ranges")) self._checkRanges();
        }]
      ];
      this._docListeners.forEach(function (l) { doc.addEventListener(l[0], l[1]); });
    },

    // The fields' values must be valid increasing pairs; else resync them.
    _checkRanges: function () {
      var el = root.document.getElementById("ctl_ranges");
      if (!el) return;
      var vals = Array.prototype.slice.call(el.querySelectorAll("input")).map(function (i) {
        return /^\s*$/.test(i.value) ? null : Number(i.value);
      });
      if (cleanRanges(vals, this.state.variables.length) === null) this.syncControls();
    },

    destroy: function () {
      var doc = root.document;
      if (doc && this._docListeners) {
        this._docListeners.forEach(function (l) { doc.removeEventListener(l[0], l[1]); });
        this._docListeners = null;
      }
      if (this._flashTimer && typeof root.clearTimeout === "function") root.clearTimeout(this._flashTimer);
      DCR.Tool.prototype.destroy.call(this);
    },

    // ---- Rendering -----------------------------------------------------------
    _build: function () {
      var self = this, doc = root.document, NS = "http://www.w3.org/2000/svg";
      var svg = doc.createElementNS(NS, "svg");
      this.el.appendChild(svg);
      var dom = { svg: svg, message: doc.createElement("div"), note: doc.createElement("div") };
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      dom.note.className = "dcr-regnote";
      dom.note.textContent = "Preview -- Done draws a new sample";
      dom.note.style.display = "none";
      this.el.appendChild(dom.note);
      this.el.appendChild(dom.message);
      this._dom = dom;
      svg.style.touchAction = "none";
      ["pointerdown", "pointermove"].forEach(function (t) {
        svg.addEventListener(t, function (ev) {
          self[t === "pointerdown" ? "_pointerDown" : "_pointerMove"](ev);
        });
      });
      ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (t) {
        svg.addEventListener(t, function (ev) { self._pointerUp(ev); });
      });
      svg.addEventListener("pointerleave", function () {
        self._hover = null;
        self._requestDraw();
      });
    },

    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      this._geo = {
        W: W, H: H, cx: W / 2, cy: H / 2 + 4,
        R: Math.max(40, Math.min(W / 2 - 100, H / 2 - 46))
      };
      this._draw();
    },

    // Redraw at most once per animation frame.
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

    _poly: function (fn) {
      var d = "", p = this.state.variables.length;
      for (var k = 0; k < p; k++) {
        var q = fn(k);
        d += (k ? "L" : "M") + q[0].toFixed(1) + "," + q[1].toFixed(1);
      }
      return d + "Z";
    },

    // The whole chart as one SVG string (text styled inline: the stylesheet's
    // `.dcr-tool svg text` rule would override attributes).
    _draw: function () {
      var dom = this._dom, L = this._geo;
      if (!dom || !L) return;
      var s = this.state, ui = this.ui, p = s.variables.length, ag = this.activeIndex();
      var self = this, o = [], k, g, r, q;
      dom.svg.setAttribute("viewBox", "0 0 " + L.W + " " + L.H);
      for (r = 1; r <= RINGS; r++) {
        o.push("<path d=\"" + this._poly(function (j) { return self._pt(j, r / RINGS); }) +
          "\" fill=\"none\" stroke=\"" + (r === RINGS ? "#c9ced6" : "#e4e7ec") + "\"/>");
      }
      for (k = 0; k < p; k++) {
        q = this._pt(k, 1);
        o.push("<line x1=\"" + L.cx + "\" y1=\"" + L.cy + "\" x2=\"" + q[0].toFixed(1) +
          "\" y2=\"" + q[1].toFixed(1) + "\" stroke=\"#c9ced6\"/>");
      }
      for (r = 0; r <= RINGS; r++) {
        q = this._pt(0, r / RINGS);
        o.push("<text x=\"" + (q[0] + 4).toFixed(1) + "\" y=\"" + (q[1] + 3).toFixed(1) +
          "\" style=\"font-size:10px;fill:#6b7785\">" +
          fmt(s.ranges[0][0] + this._range(0) * r / RINGS) + "</text>");
      }
      for (k = 0; k < p; k++) {
        q = this._pt(k, 1);
        var c = Math.cos(this._ang(k)), sn = Math.sin(this._ang(k));
        var anch = Math.abs(c) < 0.25 ? "middle" : (c > 0 ? "start" : "end");
        var lx = q[0] + c * 14, ly = q[1] + sn * 14 + (sn < -0.5 ? -8 : sn > 0.5 ? 8 : 0);
        o.push("<text x=\"" + lx.toFixed(1) + "\" y=\"" + ly.toFixed(1) + "\" text-anchor=\"" + anch +
          "\" style=\"font-size:12px;font-weight:600;fill:#1f2933\">" + esc(s.variables[k]) + "</text>");
        o.push("<text x=\"" + lx.toFixed(1) + "\" y=\"" + (ly + 13).toFixed(1) + "\" text-anchor=\"" + anch +
          "\" style=\"font-size:10px;fill:#6b7785\">[" + fmt(s.ranges[k][0]) + " - " + fmt(s.ranges[k][1]) + "]</text>");
      }
      if (ui.show) {
        var m = Math.min(s.n, PREVIEW_MAX), pv = this._previewPaths(m);
        for (g = 0; g < s.groups.length; g++) {
          o.push("<path d=\"" + pv[g] + "\" fill=\"none\" stroke=\"" + DCR.palette[g % 10] +
            "\" stroke-opacity=\"" + (g === ag ? 0.18 : 0.1) + "\" stroke-width=\"1\"/>");
        }
      }
      var order = [];
      for (g = 0; g < s.groups.length; g++) if (g !== ag) order.push(g);
      order.push(ag);
      order.forEach(function (gi) {
        var act = gi === ag, col = DCR.palette[gi % 10];
        var band = self._poly(function (j) { return self._outPt(gi, j); }) +
          self._poly(function (j) { return self._inPt(gi, j); });
        o.push("<path d=\"" + band + "\" fill=\"" + col + "\" fill-opacity=\"" + (act ? 0.22 : 0.07) +
          "\" fill-rule=\"evenodd\" stroke=\"" + col + "\" stroke-opacity=\"" +
          (act ? (ui.target === "spread" ? 0.9 : 0.5) : 0.2) + "\" stroke-width=\"1\" stroke-dasharray=\"" +
          (act ? "4 3" : "2 3") + "\"/>");
        o.push("<path d=\"" + self._poly(function (j) { return self._meanPt(gi, j); }) +
          "\" fill=\"" + col + "\" fill-opacity=\"" + (act ? 0.1 : 0.03) + "\" stroke=\"" + col +
          "\" stroke-opacity=\"" + (act ? 1 : 0.4) + "\" stroke-width=\"" + (act ? 2.5 : 1.5) +
          "\" stroke-linejoin=\"round\"/>");
      });
      var st = this._stroke, hv = this._hover, acol = DCR.palette[ag % 10];
      for (k = 0; k < p; k++) {
        var mq = this._meanPt(ag, k);
        if (ui.target === "mean") {
          var hot = (hv && hv.type === "vertex" && hv.k === k) || (st && st.type === "vertex" && st.k === k);
          o.push("<circle cx=\"" + mq[0].toFixed(1) + "\" cy=\"" + mq[1].toFixed(1) + "\" r=\"" +
            (hot ? 7 : 5.5) + "\" fill=\"#fff\" stroke=\"" + acol + "\" stroke-width=\"2\"/>");
        } else {
          o.push("<circle cx=\"" + mq[0].toFixed(1) + "\" cy=\"" + mq[1].toFixed(1) + "\" r=\"2.5\" fill=\"" + acol + "\"/>");
          [[this._outPt(ag, k), 1], [this._inPt(ag, k), -1]].forEach(function (h) {
            var on = (hv && hv.type === "sd" && hv.k === k && (hv.sign === h[1] || hv.sign === 0)) ||
              (st && st.type === "sd" && st.k === k && (st.sign === h[1] || st.sign === 0));
            var x = h[0][0].toFixed(1), y = h[0][1].toFixed(1);
            o.push("<rect x=\"" + (h[0][0] - 5).toFixed(1) + "\" y=\"" + (h[0][1] - 5).toFixed(1) +
              "\" width=\"10\" height=\"10\" rx=\"2\" transform=\"rotate(45 " + x + " " + y + ")\" fill=\"" +
              (on ? acol : "#fff") + "\" stroke=\"" + acol + "\" stroke-width=\"2\"/>");
          });
        }
      }
      if (st && st.moved) {
        var txt = this._tipText(ag, st.k);
        if (st.type === "edge") txt += "   |   " + this._tipText(ag, (st.k + 1) % p);
        var tw = txt.length * 6.6 + 10;
        var tx = clamp(st.px + 14, 4, Math.max(4, L.W - tw - 4)), ty = clamp(st.py - 14, 22, Math.max(22, L.H - 8));
        o.push("<rect x=\"" + tx.toFixed(1) + "\" y=\"" + (ty - 14).toFixed(1) + "\" width=\"" + tw.toFixed(1) +
          "\" height=\"20\" rx=\"4\" style=\"fill:#1f2933;fill-opacity:0.9\"/>");
        o.push("<text x=\"" + (tx + 5).toFixed(1) + "\" y=\"" + ty.toFixed(1) +
          "\" style=\"font-size:11.5px;fill:#fff;font-family:ui-monospace,monospace\">" + esc(txt) + "</text>");
      }
      dom.svg.innerHTML = o.join("");
      dom.note.style.display = ui.show ? "" : "none";
    },

    // Closed polylines of the first m individuals, one path per group.
    _previewPaths: function (m) {
      var s = this.state, p = s.variables.length, out = [], g, k, t;
      for (g = 0; g < s.groups.length; g++) {
        var cols = [], d = "";
        for (k = 0; k < p; k++) cols.push(this._previewVals(g, k, m));
        for (t = 0; t < m; t++) {
          for (k = 0; k < p; k++) {
            var q = this._pt(k, this._frac(k, cols[k][t]));
            d += (k ? "L" : "M") + q[0].toFixed(1) + "," + q[1].toFixed(1);
          }
          d += "Z";
        }
        out.push(d);
      }
      return out;
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

  Radar.erf = erf;
  Radar.tnormMoments = tnormMoments;
  Radar.initial = initial;
  Radar.rescale = rescale;
  Radar.rescaleSpread = rescaleSpread;
  Radar.project = project;
  Radar.spokeAngle = spokeAngle;
  DCR.register("radar", Radar);
})(typeof window !== "undefined" ? window : this);
