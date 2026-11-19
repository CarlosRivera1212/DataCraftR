/* Density tool: sculpt a smooth density curve per variable with a soft brush.
 * Undoable state (this.state, plain JSON):
 *   {variables: [names], xlim: [a, b], n,
 *    curves: [[v_1 ... v_K], ...]}   (K = 201 equally spaced points spanning
 *                                     xlim, values in 0..1, ends exactly 0)
 * Settings (this.ui, not undoable): {active, mode: "pull" | "paint", brush}.
 * brush is the Gaussian sigma as a fraction of diff(xlim), clamped to
 * [1/200, 1]. The data is a random sample of size n from the curves
 * (R/tool_density_spec.R). Curves are redrawn at most once per animation
 * frame; a gesture is one stroke and one history entry. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MARGIN = { top: 20, right: 16, bottom: 36, left: 56 };
  var K = 201;
  var MODES = ["pull", "paint"];
  var BRUSH = [0.005, 1], BRUSH_STEP = 0.005;
  var PREVIEW_PX = 26;

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function now() {
    return root.performance && root.performance.now ? root.performance.now() : Date.now();
  }

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
    return x !== null && x !== "" && isFinite(v) && v === Math.round(v) &&
      v >= lo && v <= hi ? v : null;
  }

  // Finite number (blank, boolean and arrays are not numbers), else null.
  function cleanNumber(x) {
    if (x === null || x === "" || typeof x === "boolean" || Array.isArray(x)) return null;
    var v = Number(x);
    return isFinite(v) ? v : null;
  }

  function clampBrush(v) { return clamp(v, BRUSH[0], BRUSH[1]); }

  // Map old variable indices to new ones: names present in both are kept;
  // with the same number of variables the rest are renames (paired in order).
  function remapVars(oldVars, newVars) {
    var map = oldVars.map(function (g) { return newVars.indexOf(g); });
    if (oldVars.length === newVars.length) {
      var free = newVars.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  // ---- Pure curve maths (exposed for tests) --------------------------------
  function grid(xlim, k) {
    var xs = [], i;
    k = k || K;
    for (i = 0; i < k; i++) xs.push(xlim[0] + (xlim[1] - xlim[0]) * i / (k - 1));
    xs[k - 1] = xlim[1];
    return xs;
  }

  // Values into 0..1 (NaN -> 0) and the two ends pinned to 0, in place.
  function finish(ys) {
    for (var i = 0; i < ys.length; i++) {
      var v = ys[i];
      ys[i] = v > 0 ? (v < 1 ? v : 1) : 0;   // NaN fails both tests -> 0
    }
    ys[0] = 0;
    ys[ys.length - 1] = 0;
    return ys;
  }

  function shape(kind, xlim) {
    var diff = xlim[1] - xlim[0], mid = (xlim[0] + xlim[1]) / 2;
    return finish(grid(xlim).map(function (x) {
      if (kind === "flat") return 0.5;
      if (kind === "skew") {
        var t = (x - xlim[0]) / diff;
        return 0.95 * Math.pow(t, 1.5) * Math.pow(1 - t, 5) / 0.0299 * 0.9;
      }
      return 0.85 * Math.exp(-0.5 * Math.pow((x - mid) / (diff / 6.67), 2));
    }));
  }

  // Pull: the snapshot plus dy times a Gaussian bump (centre x0) of width sigma.
  function pull(snap, xs, x0, dy, sigma) {
    var out = new Array(snap.length);
    for (var i = 0; i < snap.length; i++) {
      var z = (xs[i] - x0) / sigma;
      out[i] = snap[i] + dy * Math.exp(-0.5 * z * z);
    }
    return finish(out);
  }

  // Paint: one frame, in place. Each point moves towards the cursor height p.y
  // by its Gaussian weight times min(1, dt / 60) (dt in ms).
  function paint(ys, xs, p, sigma, dt) {
    var f = Math.min(1, dt / 60);
    if (!(f > 0)) return ys;
    for (var i = 0; i < ys.length; i++) {
      var z = (xs[i] - p.x) / sigma;
      ys[i] += (p.y - ys[i]) * Math.exp(-0.5 * z * z) * f;
    }
    return finish(ys);
  }

  // Linear interpolation of one curve onto the grid of a new xlim; 0 outside
  // the old range, ends pinned to 0.
  function resample(curve, oldXlim, newXlim) {
    var k = curve.length, xs = grid(newXlim, k), out = new Array(k);
    var span = oldXlim[1] - oldXlim[0], eps = 1e-9 * span;
    for (var j = 0; j < k; j++) {
      var x = xs[j];
      if (x < oldXlim[0] - eps || x > oldXlim[1] + eps) { out[j] = 0; continue; }
      var u = clamp((x - oldXlim[0]) / span * (k - 1), 0, k - 1);
      var i = Math.min(k - 2, Math.floor(u)), f = u - i;
      out[j] = curve[i] * (1 - f) + curve[i + 1] * f;
    }
    return finish(out);
  }

  function allZero(curve) { return !curve.some(function (v) { return v > 0; }); }

  var Density = DCR.extend(DCR.Tool, {
    init: function (o) {
      this.ui = {
        active: 0,
        mode: MODES.indexOf(o.mode) >= 0 ? o.mode : "pull",
        brush: clampBrush(cleanNumber(o.brush) || 0.12)
      };
    },

    initialState: function (o) {
      var vars = cleanNames(o.variables) || ["V1"];
      var xlim = cleanRange(o.xlim) || [0, 10];
      return {
        variables: vars,
        xlim: xlim,
        n: cleanWhole(o.n, 1, 1e6) || 100,
        curves: vars.map(function () { return shape("bell", xlim); })
      };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "density",
        variables: s.variables.slice(),
        xlim: s.xlim.slice(),
        curves: s.curves.map(function (c) { return finish(c.slice()); }),
        n: s.n
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.variables.length - 1);
    },

    // Gaussian sigma in x units.
    _sigma: function () {
      var d = this.state.xlim[1] - this.state.xlim[0];
      return clamp(this.ui.brush * d, d / 200, d);
    },

    controls: function () {
      var s = this.state;
      return {
        variables: { value: s.variables.join(", ") },
        active: {
          choices: s.variables.map(function (g, i) {
            return { value: String(i + 1), label: g, color: DCR.palette[i % 10] };
          }),
          value: String(this.activeIndex() + 1)
        },
        mode: { value: this.ui.mode },
        brush: { value: this.ui.brush },
        n: { value: s.n },
        xlim: { value: s.xlim.slice() }
      };
    },

    controlValue: function (key, value) {
      var v;
      switch (key) {
        case "variables":
          return cleanNames(typeof value === "string" ? value.split(",") : value);
        case "active":
          v = parseInt(value, 10) - 1;
          return v >= 0 && v < this.state.variables.length ? v : null;
        case "mode":
          return MODES.indexOf(value) >= 0 ? value : null;
        case "brush":
          v = cleanNumber(value);
          return v === null ? null : clampBrush(v);
        case "n":
          return cleanWhole(value, 1, 1e6);
        case "xlim":
          return cleanRange(value);
      }
      return null;
    },

    setControl: function (key, value) {
      var s = this.state, ui = this.ui, v = this.controlValue(key, value);
      if (v === null) return;
      switch (key) {
        case "variables":
          if (!same(v, s.variables)) this._setVariables(v);
          break;
        case "active":
          if (v !== ui.active) {
            ui.active = v;
            this.render();
          }
          break;
        case "mode":
        case "brush":
          if (v !== ui[key]) {
            ui[key] = v;
            this._requestDraw();
          }
          break;
        case "n":
          if (v !== s.n) this._commitWith({ n: v });
          break;
        case "xlim":
          if (!same(v, s.xlim)) this._setXlim(v);
          break;
      }
    },

    _commitWith: function (patch) {
      var next = DCR.deepCopy(this.state);
      for (var k in patch) next[k] = patch[k];
      this.commit(next);
    },

    // New xlim: every curve is resampled onto the new grid (one entry).
    _setXlim: function (xlim) {
      var s = this.state;
      this._commitWith({
        xlim: xlim,
        curves: s.curves.map(function (c) { return resample(c, s.xlim, xlim); })
      });
    },

    // New variable list: curves keep their values by name (renames pair in
    // order); new variables start as a Bell.
    _setVariables: function (vars) {
      var s = this.state, map = remapVars(s.variables, vars);
      var curves = vars.map(function () { return shape("bell", s.xlim); });
      map.forEach(function (j, i) {
        if (j >= 0) curves[j] = s.curves[i].slice();
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      // removed variables with a shaped curve: say so on the canvas
      var bell = shape("bell", s.xlim);
      var gone = s.variables.filter(function (v, i) {
        return map[i] < 0 && !allZero(s.curves[i]) && !same(s.curves[i], bell);
      });
      this._commitWith({ variables: vars, curves: curves });
      if (gone.length) this._flash(gone.join(", ") + " removed \u2014 Ctrl+Z to undo");
    },

    // Clear: every variable back to a Bell (names, range and n are kept);
    // no history entry when nothing changes.
    clear: function () {
      var s = this.state;
      var curves = s.variables.map(function () { return shape("bell", s.xlim); });
      if (!same(curves, s.curves)) this._commitWith({ curves: curves });
    },

    _setActiveCurve: function (kind) {
      var next = DCR.deepCopy(this.state);
      next.curves[this.activeIndex()] = shape(kind, next.xlim);
      if (!same(next, this.state)) this.commit(next);
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name), ui = this.ui;
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.variables.length && k !== ui.active) {
          ui.active = k;
          this.render();
          this.syncControls();
        }
      } else if (name === "bell" || name === "flat") {
        this._setActiveCurve(name);
      } else if (name === "skew") {
        this._setActiveCurve("skew");
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
    // Pointer -> {x (data, clamped to xlim), y (0..1, clamped), inside}.
    _toData: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, s = this.state;
      var px = ev.clientX - r.left, py = ev.clientY - r.top;
      var t = clamp((px - L.left) / L.width, 0, 1);
      return {
        x: s.xlim[0] + t * (s.xlim[1] - s.xlim[0]),
        y: clamp((L.top + L.height - py) / L.height, 0, 1),
        inside: px >= L.left && px <= L.left + L.width &&
          py >= L.top && py <= L.top + L.height
      };
    },

    _pointerDown: function (ev) {
      if (ev.button !== 0 || this._stroke || !this._geo) return;
      var p = this._toData(ev);
      if (!p.inside) return;
      this._dom.svg.setPointerCapture(ev.pointerId);
      var i = this.activeIndex();
      this._stroke = {
        id: ev.pointerId, i: i, x0: p.x, y0: p.y, sigma: this._sigma(),
        start: this.state.curves[i].slice(), last: now()
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
      if (st && ev.pointerId === st.id) {
        var s = this.state, xs = grid(s.xlim, s.curves[st.i].length), t = now();
        if (this.ui.mode === "pull") {
          s.curves[st.i] = pull(st.start, xs, st.x0, p.y - st.y0, st.sigma);
        } else {
          paint(s.curves[st.i], xs, p, this._sigma(), t - st.last);
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
      if (!same(this.state.curves[st.i], st.start)) this.commit(this.state);
      else this.render();
      this.endStroke();
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
        yTitle: svg.append("text").attr("text-anchor", "middle").text("relative density"),
        clip: svg.append("clipPath").attr("id", "dcr-density-clip").append("rect"),
        plot: svg.append("g").attr("clip-path", "url(#dcr-density-clip)")
          .style("pointer-events", "none"),
        message: document.createElement("div")
      };
      dom.curves = dom.plot.append("g");
      dom.cursorLine = dom.plot.append("line").attr("stroke", "#447099")
        .attr("stroke-opacity", 0.25).style("display", "none");
      dom.preview = dom.plot.append("path").attr("fill", "none")
        .attr("stroke", "#447099").attr("stroke-dasharray", "3 3")
        .style("display", "none");
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
      var d3 = root.d3, dom = this._dom, s = this.state;
      var L = this._geo = {
        left: MARGIN.left, top: MARGIN.top,
        width: Math.max(1, W - MARGIN.left - MARGIN.right),
        height: Math.max(1, H - MARGIN.top - MARGIN.bottom)
      };
      var x = d3.scaleLinear().domain(s.xlim).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain([0, 1]).range([L.top + L.height, L.top]);
      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.clip.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).ticks(Math.max(2, Math.round(L.width / 80))));
      dom.yTitle.attr("transform", "translate(12," + (L.top + L.height / 2) + ") rotate(-90)");
      this._drawCurves();
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

    // One area + one line per variable, updated in place; the elements are
    // rebuilt only when the variable count or the active variable changes.
    _drawCurves: function () {
      var dom = this._dom, L = this._geo;
      if (!dom || !dom.curves || !L) return;
      var s = this.state, act = this.activeIndex();
      var key = s.variables.length + ":" + act;
      if (this._curveKey !== key) {
        this._curveKey = key;
        dom.curves.selectAll("*").remove();
        dom.items = [];
        // inactive variables first (faint dashed outlines), the active one on top
        s.variables.map(function (v, i) { return i; })
          .filter(function (i) { return i !== act; }).concat([act])
          .forEach(function (i) {
            var col = DCR.palette[i % 10], on = i === act, item = { i: i };
            if (on) {
              item.area = dom.curves.append("path").attr("fill", col)
                .attr("fill-opacity", 0.12);
            }
            item.line = dom.curves.append("path").attr("fill", "none")
              .attr("stroke", col).attr("stroke-width", on ? 2.5 : 1.5)
              .attr("stroke-opacity", on ? 1 : 0.45)
              .attr("stroke-dasharray", on ? null : "5 3");
            dom.items.push(item);
          });
      }
      var xs = grid(s.xlim, K), px = [], bottom = L.top + L.height, j;
      for (j = 0; j < K; j++) px.push((L.left + j / (K - 1) * L.width).toFixed(1));
      dom.items.forEach(function (item) {
        var c = s.curves[item.i], d = "";
        for (j = 0; j < c.length; j++) {
          d += (j ? "L" : "M") + px[j] + "," + (bottom - c[j] * L.height).toFixed(1);
        }
        item.line.attr("d", d);
        if (item.area) item.area.attr("d", d + "L" + px[K - 1] + "," + bottom + "L" + px[0] + "," + bottom + "Z");
      });

      // brush preview: the Gaussian falloff under the cursor
      if (this._cursor === null || this._cursor === undefined) {
        dom.preview.style("display", "none");
        dom.cursorLine.style("display", "none");
        return;
      }
      var sigma = this._sigma(), c0 = this._cursor, pd = "";
      for (j = 0; j < K; j++) {
        var z = (xs[j] - c0) / sigma, w = Math.exp(-0.5 * z * z);
        if (w > 0.01) {
          pd += (pd ? "L" : "M") + px[j] + "," + (bottom - w * PREVIEW_PX).toFixed(1);
        }
      }
      var cx = L.left + (c0 - s.xlim[0]) / (s.xlim[1] - s.xlim[0]) * L.width;
      dom.preview.attr("d", pd || null).style("display", pd ? null : "none");
      dom.cursorLine.attr("x1", cx).attr("x2", cx).attr("y1", L.top).attr("y2", bottom)
        .style("display", null);
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

  Density.pull = pull;
  Density.paint = paint;
  Density.resample = resample;
  Density.shape = shape;
  Density.grid = grid;
  DCR.register("density", Density);
})(typeof window !== "undefined" ? window : this);
