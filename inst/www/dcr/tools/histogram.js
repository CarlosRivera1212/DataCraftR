/* Histogram tool: paint bar heights (relative weights) for one histogram per
 * variable.
 * Undoable state (this.state, plain JSON):
 *   {variables: [names], xlim: [a, b], nbins, n,
 *    weights: [[w_1 ... w_nbins], ...]}   (one row per variable, each in 0..1)
 * Settings (this.ui, not undoable): {active}.
 * The weights are the shape of the population; the data is a random sample of
 * size n from it (R/tool_histogram_spec.R). Bars span exactly xlim. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MARGIN = { top: 20, right: 16, bottom: 36, left: 56 };

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function zeros(k) {
    var out = [];
    for (var i = 0; i < k; i++) out.push(0);
    return out;
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

  // Resample one weight row onto new bins. The weights are a piecewise
  // constant density over the old bins; each new bin gets the average of that
  // density over it (so the mass is preserved, and parts outside the old
  // range count as 0). The result is scaled so its maximum equals the old one.
  function rebin(row, oldLim, newLim, newN) {
    var oldN = row.length, out = [], i, j;
    var oldW = (oldLim[1] - oldLim[0]) / oldN;
    var newW = (newLim[1] - newLim[0]) / newN;
    var oldMax = Math.max.apply(null, row.concat([0]));
    for (i = 0; i < newN; i++) {
      // bin edges in old-bin units
      var u0 = (newLim[0] + i * newW - oldLim[0]) / oldW;
      var u1 = (newLim[0] + (i + 1) * newW - oldLim[0]) / oldW;
      var lo = Math.max(0, Math.floor(u0)), hi = Math.min(oldN, Math.ceil(u1));
      var mass = 0;
      for (j = lo; j < hi; j++) {
        mass += row[j] * Math.max(0, Math.min(u1, j + 1) - Math.max(u0, j));
      }
      out.push(mass / (u1 - u0));
    }
    var newMax = Math.max.apply(null, out);
    if (newMax > 0) {
      var f = oldMax / newMax;
      out = out.map(function (v) { return clamp(v * f, 0, 1); });
    }
    return out;
  }

  var Histogram = DCR.extend(DCR.Tool, {
    init: function () {
      this.ui = { active: 0 };
    },

    initialState: function (o) {
      var vars = cleanNames(o.variables) || ["V1"];
      var nbins = cleanWhole(o.nbins, 1, 100) || 10;
      return {
        variables: vars,
        xlim: cleanRange(o.xlim) || [0, 10],
        nbins: nbins,
        n: cleanWhole(o.n, 1, 1e6) || 100,
        weights: vars.map(function () { return zeros(nbins); })
      };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "histogram",
        variables: s.variables.slice(),
        xlim: s.xlim.slice(),
        nbins: s.nbins,
        weights: s.weights.map(function (row) {
          return row.map(function (v) { return v > 0 ? v : 0; });
        }),
        n: s.n
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.variables.length - 1);
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
        n: { value: s.n },
        xlim: { value: s.xlim.slice() },
        nbins: { value: s.nbins }
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
        case "n":
          return cleanWhole(value, 1, 1e6);
        case "nbins":
          return cleanWhole(value, 1, 100);
        case "xlim":
          return cleanRange(value);
      }
      return null;
    },

    setControl: function (key, value) {
      var s = this.state, v = this.controlValue(key, value);
      if (v === null) return;
      switch (key) {
        case "variables":
          if (!same(v, s.variables)) this._setVariables(v);
          break;
        case "active":
          this.ui.active = v;
          this.render();
          break;
        case "n":
          if (v !== s.n) this._commitWith({ n: v });
          break;
        case "nbins":
          if (v !== s.nbins) this._rebin(s.xlim, v);
          break;
        case "xlim":
          if (!same(v, s.xlim)) this._rebin(v, s.nbins);
          break;
      }
    },

    _commitWith: function (patch) {
      var next = DCR.deepCopy(this.state);
      for (var k in patch) next[k] = patch[k];
      this.commit(next);
    },

    // New xlim and/or nbins: every variable is resampled onto the new bins.
    _rebin: function (xlim, nbins) {
      var s = this.state;
      this._commitWith({
        xlim: xlim,
        nbins: nbins,
        weights: s.weights.map(function (row) { return rebin(row, s.xlim, xlim, nbins); })
      });
    },

    // New variable list: weights keep their values by name (renames pair in
    // order); new variables start at zero.
    _setVariables: function (vars) {
      var s = this.state, map = remapVars(s.variables, vars);
      var weights = vars.map(function () { return zeros(s.nbins); });
      map.forEach(function (j, i) {
        if (j >= 0) weights[j] = s.weights[i].slice();
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      // removed variables that had bars: say so on the canvas
      var gone = s.variables.filter(function (v, i) {
        return map[i] < 0 && s.weights[i].some(function (w) { return w > 0; });
      });
      this._commitWith({ variables: vars, weights: weights });
      if (gone.length) this._flash(gone.join(", ") + " removed \u2014 Ctrl+Z to undo");
    },

    // Clear zeroes every variable; no history entry if all are zero already.
    clear: function () {
      var s = this.state, w = s.variables.map(function () { return zeros(s.nbins); });
      if (!same(w, s.weights)) this._commitWith({ weights: w });
    },

    // Set the active variable's bars to `row` (a function of the bin count).
    _setActiveRow: function (row) {
      var next = DCR.deepCopy(this.state);
      next.weights[this.activeIndex()] = row;
      if (!same(next, this.state)) this.commit(next);
    },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name);
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.variables.length && k !== this.ui.active) {
          this.ui.active = k;
          this.render();
          this.syncControls();
        }
      } else if (name === "flat") {
        this._setActiveRow(zeros(this.state.nbins).map(function () { return 0.5; }));
      } else if (name === "reset") {
        this._setActiveRow(zeros(this.state.nbins));
      }
    },

    // ---- Painting: one drag = one history entry ------------------------------
    _pointerDown: function (ev) {
      if (ev.button !== 0) return;
      if (this._stroke) {
        // a stroke whose end event never came (lost capture): finish it first
        var old = this._stroke, svg = this._dom.svg;
        var held = typeof svg.hasPointerCapture === "function" && svg.hasPointerCapture(old.id);
        if (ev.pointerId !== old.id && held) return;
        this._pointerUp({ pointerId: old.id });
      }
      var p = this._toBar(ev), L = this._geo;
      if (!p.inside) return;
      this._dom.svg.setPointerCapture(ev.pointerId);
      this._stroke = {
        id: ev.pointerId, i: this.activeIndex(), last: null,
        start: this.state.weights[this.activeIndex()].slice()
      };
      this.beginStroke();
      this._paint(p);
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._paint(this._toBar(ev));
    },

    // Set the bin under the pointer to the pointer's height; bins skipped
    // since the last event are filled by interpolation.
    _paint: function (p) {
      var st = this._stroke, row = this.state.weights[st.i];
      var from = st.last || p, a = from.bin, b = p.bin, d = Math.abs(b - a);
      for (var k = 0; k <= d; k++) {
        var t = d === 0 ? 1 : k / d;
        var bin = a + Math.round((b - a) * t);
        row[bin] = from.h + (p.h - from.h) * t;
      }
      st.last = { bin: b, h: p.h };
      this.render();
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      try {
        if (!same(this.state.weights[st.i], st.start)) this.commit(this.state);
        else this.render();
      } finally {
        this.endStroke();
      }
    },

    // Pointer -> {bin, h (0..1, clamped), inside (within the plot area)}.
    _toBar: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, s = this.state;
      var x = ev.clientX - r.left, y = ev.clientY - r.top;
      return {
        bin: clamp(Math.floor((x - L.left) / L.width * s.nbins), 0, s.nbins - 1),
        h: clamp((L.top + L.height - y) / L.height, 0, 1),
        inside: x >= L.left && x <= L.left + L.width &&
          y >= L.top && y <= L.top + L.height
      };
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
        yTitle: svg.append("text").attr("text-anchor", "middle").text("relative weight"),
        clip: svg.append("clipPath").attr("id", "dcr-histogram-clip").append("rect"),
        plot: svg.append("g").attr("clip-path", "url(#dcr-histogram-clip)"),
        labels: svg.append("g").style("pointer-events", "none"),
        message: document.createElement("div")
      };
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      this.el.appendChild(dom.message);
      this._dom = dom;
      ["pointerdown", "pointermove"].forEach(function (t) {
        dom.svg.addEventListener(t, function (ev) {
          self[t === "pointerdown" ? "_pointerDown" : "_pointerMove"](ev);
        });
      });
      ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (t) {
        dom.svg.addEventListener(t, function (ev) { self._pointerUp(ev); });
      });
    },

    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      var d3 = root.d3, dom = this._dom, s = this.state, self = this;
      var L = this._geo = {
        left: MARGIN.left, top: MARGIN.top,
        width: Math.max(1, W - MARGIN.left - MARGIN.right),
        height: Math.max(1, H - MARGIN.top - MARGIN.bottom)
      };
      var x = d3.scaleLinear().domain(s.xlim).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain([0, 1]).range([L.top + L.height, L.top]);
      var bw = L.width / s.nbins;

      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.clip.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).ticks(Math.max(2, Math.round(L.width / 80))));
      dom.yTitle.attr("transform", "translate(12," + (L.top + L.height / 2) + ") rotate(-90)");

      var act = this.activeIndex();
      dom.plot.selectAll("*").remove();
      dom.labels.selectAll("*").remove();
      // Inactive variables: faint outlines; the active one is filled on top.
      var order = s.variables.map(function (v, i) { return i; })
        .filter(function (i) { return i !== act; }).concat([act]);
      order.forEach(function (i) {
        var col = DCR.palette[i % 10], on = i === act;
        s.weights[i].forEach(function (w, b) {
          dom.plot.append("rect")
            .attr("x", L.left + b * bw).attr("width", bw)
            .attr("y", y(w)).attr("height", Math.max(0, L.top + L.height - y(w)))
            .attr("fill", on ? col : "none").attr("fill-opacity", on ? 0.55 : 0)
            .attr("stroke", col).attr("stroke-opacity", on ? 1 : 0.4)
            .attr("stroke-width", on ? 1.5 : 1)
            .style("pointer-events", "none");
        });
      });

      // Expected counts of the active variable, round(w / sum(w) * n).
      var row = s.weights[act], tot = row.reduce(function (a, v) { return a + v; }, 0);
      if (tot > 0) {
        var counts = row.map(function (w) { return Math.round(w / tot * s.n); });
        var digits = String(Math.max.apply(null, counts)).length;
        if (bw >= digits * 6 + 2) {
          counts.forEach(function (c, b) {
            if (c <= 0) return;
            dom.labels.append("text").attr("text-anchor", "middle")
              .attr("x", L.left + (b + 0.5) * bw).attr("y", y(row[b]) - 3)
              .text(c);
          });
        }
      }
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

  Histogram.rebin = rebin;
  DCR.register("histogram", Histogram);
})(typeof window !== "undefined" ? window : this);
