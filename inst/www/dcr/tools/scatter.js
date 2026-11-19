/* Scatter tool: spray / point / erase points for up to 10 groups.
 * Undoable state (this.state, plain JSON):
 *   {xlim: [a, b], ylim: [a, b], groups: [names], names: {x, y, group},
 *    points: {x: [...], y: [...], g: [group index]}}
 * Settings (this.ui, not undoable): {active, mode, brush, density}.
 * Points are kept in data units; the canvas only displays them. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MODES = ["spray", "point", "erase"];
  var BRUSH = [0.01, 0.5], DENSITY = [5, 200];
  var MARGIN = { top: 12, right: 14, bottom: 36, left: 46 };
  var POINT_RADIUS = 3;

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  // Coordinates are rounded relative to their scale (a millionth of the
  // order of magnitude of the axis range, or of the points' own spread when
  // that is smaller, e.g. after zooming out), never to a fixed number of
  // significant digits, so an offset range such as 1e5..1e5+10 cannot
  // collapse the points (same rule as boxplot.js).
  function roundStep(lim, v) {
    var d = lim[1] - lim[0];
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < v.length; i++) {      // no apply(): may be millions
      if (v[i] < lo) lo = v[i];
      if (v[i] > hi) hi = v[i];
    }
    if (hi - lo > 0 && hi - lo < d) d = hi - lo;
    return Math.pow(10, Math.floor(Math.log10(d)) - 6);
  }
  function roundAll(v, lim) {
    var h = roundStep(lim, v);
    return v.map(function (u) { return Number((Math.round(u / h) * h).toPrecision(15)); });
  }

  // Valid group/variable names, trimmed like R's check_names(), or null.
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

  function cleanVarNames(x) {
    if (!x || typeof x !== "object") return null;
    var v = cleanNames([x.x, x.y, x.group].map(function (s) { return s == null ? "" : s; }));
    return v && v.length === 3 ? { x: v[0], y: v[1], group: v[2] } : null;
  }

  // Map old group indices to new ones when the group list changes: names
  // present in both keep their points; with the same number of groups the
  // remaining ones are renames (paired in order); other old groups are gone.
  function remapGroups(oldGroups, newGroups) {
    var map = oldGroups.map(function (g) {
      var j = newGroups.indexOf(g);
      return j >= 0 ? j : -1;
    });
    if (oldGroups.length === newGroups.length) {
      var free = newGroups.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  function removedMessage(counts) {
    var n = 0, names = [];
    Object.keys(counts).forEach(function (g) { n += counts[g]; names.push(g); });
    return n + (n === 1 ? " point" : " points") + " of " + names.join(", ") +
      " removed \u2014 Ctrl+Z to undo";
  }

  var Scatter = DCR.extend(DCR.Tool, {
    init: function (o) {
      this.ui = {
        active: 0,
        mode: MODES.indexOf(o.mode) >= 0 ? o.mode : "spray",
        brush: clamp(Number(o.brush) || 0.08, BRUSH[0], BRUSH[1]),
        density: clamp(Number(o.density) || 40, DENSITY[0], DENSITY[1])
      };
    },

    initialState: function (o) {
      return {
        xlim: cleanRange(o.xlim) || [0, 10],
        ylim: cleanRange(o.ylim) || [0, 10],
        groups: cleanNames(o.groups) || ["A", "B", "C"],
        names: cleanVarNames(o.names) || { x: "x", y: "y", group: "group" },
        points: { x: [], y: [], g: [] }
      };
    },

    toSpec: function () {
      var s = this.state, groups = s.groups;
      return {
        tool: "scatter",
        xlim: s.xlim.slice(),
        ylim: s.ylim.slice(),
        names: { x: s.names.x, y: s.names.y, group: s.names.group },
        groups: groups.slice(),
        points: {
          x: roundAll(s.points.x, s.xlim),
          y: roundAll(s.points.y, s.ylim),
          group: s.points.g.map(function (i) { return groups[i]; })
        }
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
        brush: { value: this.ui.brush },
        density: { value: this.ui.density },
        xlim: { value: s.xlim.slice() },
        ylim: { value: s.ylim.slice() },
        names: { value: { x: s.names.x, y: s.names.y, group: s.names.group } }
      };
    },

    // A control value in tool units, or null when invalid. Accepts both what
    // R forwards and what controls() pushes (groups as "A, B" text).
    controlValue: function (key, value) {
      var v, lim;
      switch (key) {
        case "groups":
          return cleanNames(typeof value === "string" ? value.split(",") : value);
        case "active":
          v = parseInt(value, 10) - 1;
          return v >= 0 && v < this.state.groups.length ? v : null;
        case "mode":
          return MODES.indexOf(value) >= 0 ? value : null;
        case "brush":
        case "density":
          v = Number(value);
          lim = key === "brush" ? BRUSH : DENSITY;
          return isFinite(v) && v >= lim[0] && v <= lim[1] ? v : null;
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
          if (!same(v, s.groups)) this._setGroups(v);
          break;
        case "active":
          ui.active = v;
          this._drawBrush();
          break;
        case "mode":
        case "brush":
        case "density":
          if (v !== ui[key]) {
            ui[key] = v;
            this._drawBrush();
          }
          break;
        case "xlim":
        case "ylim":
        case "names":
          if (!same(v, s[key])) this._commitWith(key, v);
          break;
      }
    },

    // History budget: about 3 million points over all undo steps.
    stateSize: function (s) { return s.points.x.length; },
    historyBudget: 3e6,

    _commitWith: function (key, value) {
      var next = DCR.deepCopy(this.state);
      next[key] = value;
      this.commit(next);
    },

    // New group list: remap point indices, drop points of removed groups
    // (one undoable step) and say so on the canvas.
    _setGroups: function (groups) {
      var s = this.state, map = remapGroups(s.groups, groups);
      var pts = { x: [], y: [], g: [] }, removed = {};
      for (var i = 0; i < s.points.g.length; i++) {
        var j = map[s.points.g[i]];
        if (j >= 0) {
          pts.x.push(s.points.x[i]);
          pts.y.push(s.points.y[i]);
          pts.g.push(j);
        } else {
          var name = s.groups[s.points.g[i]];
          removed[name] = (removed[name] || 0) + 1;
        }
      }
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      var next = DCR.deepCopy(s);
      next.groups = groups;
      next.points = pts;
      this.commit(next);
      if (Object.keys(removed).length) this._flash(removedMessage(removed));
    },

    // Clear erases the drawing; groups, ranges and names stay.
    clear: function () {
      if (!this.state.points.x.length) return;
      this._commitWith("points", { x: [], y: [], g: [] });
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name);
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.groups.length && k !== this.ui.active) {
          this.ui.active = k;
          this._drawBrush();
          this.syncControls();
        }
      } else if (name === "brush-up" || name === "brush-down") {
        var b = this.ui.brush + (name === "brush-up" ? 0.01 : -0.01);
        b = clamp(Math.round(b * 100) / 100, BRUSH[0], BRUSH[1]);
        if (b !== this.ui.brush) {
          this.ui.brush = b;
          this._drawBrush();
          this.syncControls();
        }
      }
    },

    // ---- Drawing data (data units) -----------------------------------------
    _inside: function (x, y) {
      var s = this.state;
      return x >= s.xlim[0] && x <= s.xlim[1] && y >= s.ylim[0] && y <= s.ylim[1];
    },

    _radius: function () {
      return this.ui.brush * (this.state.xlim[1] - this.state.xlim[0]);
    },

    // Add up to n points uniform in the brush disc around (cx, cy), keeping
    // only those inside the ranges. Returns the number added.
    _spray: function (cx, cy, n) {
      var p = this.state.points, R = this._radius(), g = this.activeIndex(), added = 0;
      for (var i = 0; i < n; i++) {
        var r = R * Math.sqrt(Math.random()), t = 2 * Math.PI * Math.random();
        var x = cx + r * Math.cos(t), y = cy + r * Math.sin(t);
        if (!this._inside(x, y)) continue;
        p.x.push(x); p.y.push(y); p.g.push(g);
        added++;
      }
      return added;
    },

    _addPoint: function (x, y) {
      if (!this._inside(x, y)) return false;
      var p = this.state.points;
      p.x.push(x); p.y.push(y); p.g.push(this.activeIndex());
      return true;
    },

    // Remove points (any group) within the brush radius. Returns the count.
    _erase: function (cx, cy) {
      var p = this.state.points, R2 = Math.pow(this._radius(), 2);
      var keep = { x: [], y: [], g: [] };
      for (var i = 0; i < p.x.length; i++) {
        var dx = p.x[i] - cx, dy = p.y[i] - cy;
        if (dx * dx + dy * dy <= R2) continue;
        keep.x.push(p.x[i]); keep.y.push(p.y[i]); keep.g.push(p.g[i]);
      }
      var removed = p.x.length - keep.x.length;
      if (removed) this.state.points = keep;
      return removed;
    },

    // ---- Pointer strokes: one stroke = one history entry ------------------
    _pointerDown: function (ev) {
      // No preventDefault: the press must still blur a sidebar field so its
      // value is committed (touch scrolling is off via CSS touch-action).
      if (ev.button !== 0 || this._stroke) return;
      var d = this._toData(ev), self = this;
      this._dom.svg.setPointerCapture(ev.pointerId);
      this._moveBrush(ev);
      if (this.ui.mode === "point") {
        if (this._addPoint(d.x, d.y)) this.commit(this.state);
        return;
      }
      var st = { id: ev.pointerId, x: d.x, y: d.y, changed: false };
      this._stroke = st;
      this.beginStroke();
      if (this.ui.mode === "erase") {
        this._eraseAt(st);
        return;
      }
      // Spray: density * dt points per frame; the carry starts at 1 so a
      // tap leaves one point.
      st.carry = 1;
      st.t = root.performance.now();
      var tick = function (now) {
        if (self._stroke !== st) return;
        var dt = clamp((now - st.t) / 1000, 0, 0.1);
        st.t = now;
        var want = self.ui.density * dt + st.carry, n = Math.floor(want);
        st.carry = want - n;
        var from = self.state.points.x.length;
        if (n > 0 && self._spray(st.x, st.y, n) > 0) {
          st.changed = true;
          self._drawPoints(from);
        }
        st.raf = root.requestAnimationFrame(tick);
      };
      st.raf = root.requestAnimationFrame(tick);
    },

    _eraseAt: function (st) {
      if (this._erase(st.x, st.y) > 0) {
        st.changed = true;
        this._drawPoints(0);
      }
    },

    _pointerMove: function (ev) {
      this._moveBrush(ev);
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      var d = this._toData(ev);
      st.x = d.x;
      st.y = d.y;
      if (this.ui.mode === "erase") this._eraseAt(st);
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke:
    // commit it, then apply what was queued meanwhile (controls, undo).
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      if (st.raf) root.cancelAnimationFrame(st.raf);
      this._stroke = null;
      if (st.changed) this.commit(this.state);
      this.endStroke();
    },

    // ---- Rendering ---------------------------------------------------------
    _build: function () {
      var el = this.el, self = this, d3 = root.d3;
      var canvas = document.createElement("canvas");
      el.appendChild(canvas);
      var svg = d3.select(el).append("svg");
      var dom = {
        canvas: canvas,
        svg: svg.node(),
        frame: svg.append("rect").attr("class", "dcr-frame")
          .attr("fill", "none").attr("stroke", "#c9ced6"),
        xAxis: svg.append("g"),
        yAxis: svg.append("g"),
        xTitle: svg.append("text").attr("text-anchor", "middle"),
        yTitle: svg.append("text").attr("text-anchor", "middle"),
        brush: svg.append("circle").attr("fill", "none").attr("stroke-width", 1.5)
          .style("display", "none"),
        message: document.createElement("div")
      };
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      el.appendChild(dom.message);
      this._dom = dom;
      dom.svg.addEventListener("pointerdown", function (ev) { self._pointerDown(ev); });
      dom.svg.addEventListener("pointermove", function (ev) { self._pointerMove(ev); });
      dom.svg.addEventListener("pointerup", function (ev) { self._pointerUp(ev); });
      dom.svg.addEventListener("pointercancel", function (ev) { self._pointerUp(ev); });
      dom.svg.addEventListener("lostpointercapture", function (ev) { self._pointerUp(ev); });
      dom.svg.addEventListener("pointerleave", function () {
        if (!self._stroke) dom.brush.style("display", "none");
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

    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      var d3 = root.d3, dom = this._dom, s = this.state;
      var L = this._geo = this._layout(W, H);

      var dpr = root.devicePixelRatio || 1;
      dom.canvas.width = Math.round(W * dpr);
      dom.canvas.height = Math.round(H * dpr);
      dom.canvas.getContext("2d").setTransform(dpr, 0, 0, dpr, 0, 0);
      this._drawPoints(0);

      var x = d3.scaleLinear().domain(s.xlim).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain(s.ylim).range([L.top + L.height, L.top]);
      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).ticks(Math.max(2, Math.round(L.width / 70))));
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xTitle.attr("x", L.left + L.width / 2).attr("y", L.top + L.height + 30)
        .text(s.names.x);
      dom.yTitle.attr("transform", "translate(" + (L.left - 34) + "," +
                      (L.top + L.height / 2) + ") rotate(-90)")
        .text(s.names.y);
      this._drawBrush();
    },

    // Draw points from index `from` on (0 = clear and redraw all), one path
    // per group, clipped to the plot area.
    _drawPoints: function (from) {
      if (!this._dom || !this._geo) return;
      var L = this._geo, p = this.state.points, n = this.state.groups.length;
      var ctx = this._dom.canvas.getContext("2d");
      if (from === 0) ctx.clearRect(0, 0, L.W, L.H);
      var paths = [];
      for (var gi = 0; gi < n; gi++) paths.push(new root.Path2D());
      for (var i = from; i < p.x.length; i++) {
        var q = this._px(p.x[i], p.y[i]), path = paths[p.g[i]];
        if (!path) continue;
        path.moveTo(q[0] + POINT_RADIUS, q[1]);
        path.arc(q[0], q[1], POINT_RADIUS, 0, 2 * Math.PI);
      }
      ctx.save();
      ctx.beginPath();
      ctx.rect(L.left, L.top, L.width, L.height);
      ctx.clip();
      ctx.globalAlpha = 0.8;
      paths.forEach(function (path, g) {
        ctx.fillStyle = DCR.palette[g % 10];
        ctx.fill(path);
      });
      ctx.restore();
    },

    _drawBrush: function () {
      if (!this._dom || !this._geo) return;
      var erase = this.ui.mode === "erase";
      this._dom.brush
        .attr("r", this.ui.mode === "point" ? POINT_RADIUS + 2 : this._radius() * this._geo.k)
        .attr("stroke", erase ? "#6b7785" : DCR.palette[this.activeIndex() % 10])
        .attr("stroke-dasharray", erase ? "4 3" : null);
    },

    _moveBrush: function (ev) {
      var r = this.el.getBoundingClientRect();
      this._dom.brush.style("display", null)
        .attr("cx", ev.clientX - r.left).attr("cy", ev.clientY - r.top);
    },

    _flash: function (text) {
      if (!this._dom) return;
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

  DCR.register("scatter", Scatter);
})(typeof window !== "undefined" ? window : this);
