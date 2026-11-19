/* Count tool: paint the exact integer count of every (variable, category) as
 * grouped bars (categories on x, one bar per variable inside each category).
 * Undoable state (this.state, plain JSON):
 *   {variables: [names], categories: [names], ymax,
 *    counts: [[c_1 ... c_ncat], ...]}   (one row per variable, integers >= 0)
 * Settings (this.ui, not undoable): {active} (a highlighted variable only).
 * The data is exactly these counts (R/tool_count_spec.R). Counts are integers
 * in the state at all times, and are never truncated by a lower ymax. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MARGIN = { top: 30, right: 16, bottom: 36, left: 56 };
  var YMAX_MAX = 1e6;
  var TOTAL_MAX = 1e6;     // cap on the total number of observations
  var GROUP_PAD = 0.2;     // share of each category slot left empty

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function fill(k, v) {
    var out = [];
    for (var i = 0; i < k; i++) out.push(v);
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

  function cleanWhole(x, lo, hi) {
    var v = Array.isArray(x) ? NaN : Number(x);
    return x !== null && x !== "" && isFinite(v) && v === Math.round(v) &&
      v >= lo && v <= hi ? v : null;
  }

  // Map old level indices to new ones: names present in both are kept; with
  // the same number of levels the rest are renames (paired in order).
  function remap(oldNames, newNames) {
    var map = oldNames.map(function (g) { return newNames.indexOf(g); });
    if (oldNames.length === newNames.length) {
      var free = newNames.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  function maxCount(counts) {
    var m = 0;
    counts.forEach(function (row) {
      row.forEach(function (c) { if (c > m) m = c; });
    });
    return m;
  }

  // "N observations of a, b removed - Ctrl+Z to undo" for removed levels
  // (old index i with map[i] < 0) whose counts sumOf(i) are not zero.
  function removedMessage(names, map, sumOf) {
    var n = 0, gone = [];
    names.forEach(function (g, i) {
      var k = map[i] < 0 ? sumOf(i) : 0;
      if (k > 0) { n += k; gone.push(g); }
    });
    if (!gone.length) return null;
    return n + (n === 1 ? " observation" : " observations") + " of " +
      gone.join(", ") + " removed \u2014 Ctrl+Z to undo";
  }

  function total(counts) {
    var t = 0;
    counts.forEach(function (row) { row.forEach(function (c) { t += c; }); });
    return t;
  }

  var Count = DCR.extend(DCR.Tool, {
    init: function () {
      this.ui = { active: 0 };
    },

    initialState: function (o) {
      var vars = cleanNames(o.variables) || ["V1", "V2"];
      var cats = cleanNames(o.categories) || ["C1", "C2", "C3"];
      var ymax = cleanWhole(o.ymax, 1, YMAX_MAX) || 20;
      return {
        variables: vars,
        categories: cats,
        ymax: ymax,
        counts: vars.map(function () { return fill(cats.length, Math.min(5, ymax)); })
      };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "count",
        variables: s.variables.slice(),
        categories: s.categories.slice(),
        counts: s.counts.map(function (row) { return row.slice(); })
      };
    },

    activeIndex: function () {
      return Math.min(this.ui.active, this.state.variables.length - 1);
    },

    controls: function () {
      var s = this.state;
      return {
        variables: { value: s.variables.join(", ") },
        categories: { value: s.categories.join(", ") },
        ymax: { value: s.ymax }
      };
    },

    controlValue: function (key, value) {
      switch (key) {
        case "variables":
        case "categories":
          return cleanNames(typeof value === "string" ? value.split(",") : value);
        case "ymax":
          return cleanWhole(value, 1, YMAX_MAX);
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
        case "categories":
          if (!same(v, s.categories)) this._setCategories(v);
          break;
        case "ymax":
          this._setYmax(v);
          break;
      }
    },

    _commitWith: function (patch) {
      var next = DCR.deepCopy(this.state);
      for (var k in patch) next[k] = patch[k];
      this.commit(next);
    },

    // A ymax below an existing count is raised back to the largest count.
    _setYmax: function (v) {
      var s = this.state, top = maxCount(s.counts), raised = v < top;
      if (raised) v = top;
      if (v !== s.ymax) this._commitWith({ ymax: v });
      else if (raised) this.syncControls();   // put the kept value back in the field
      if (raised) this._flash("Y max raised to " + v + " to keep your counts");
    },

    // New variable list: counts keep their values by name (renames pair in
    // order); new variables start at zero.
    _setVariables: function (vars) {
      var s = this.state, map = remap(s.variables, vars);
      var counts = vars.map(function () { return fill(s.categories.length, 0); });
      map.forEach(function (j, i) {
        if (j >= 0) counts[j] = s.counts[i].slice();
      });
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      var msg = removedMessage(s.variables, map, function (i) {
        return s.counts[i].reduce(function (a, c) { return a + c; }, 0);
      });
      this._commitWith({ variables: vars, counts: counts });
      if (msg) this._flash(msg);
    },

    _setCategories: function (cats) {
      var s = this.state, map = remap(s.categories, cats);
      var counts = s.counts.map(function (row) {
        var out = fill(cats.length, 0);
        map.forEach(function (j, i) { if (j >= 0) out[j] = row[i]; });
        return out;
      });
      var msg = removedMessage(s.categories, map, function (j) {
        return s.counts.reduce(function (a, row) { return a + row[j]; }, 0);
      });
      this._commitWith({ categories: cats, counts: counts });
      if (msg) this._flash(msg);
    },

    // Set every bar to `v`; no history entry if nothing changes.
    _setAll: function (v) {
      var next = DCR.deepCopy(this.state);
      var cap = Math.floor(TOTAL_MAX / (next.variables.length * next.categories.length));
      if (v > cap) {
        v = cap;
        this._flash("Total capped at 1e6 observations: bars set to " + cap);
      }
      next.counts = next.counts.map(function (row) { return fill(row.length, v); });
      if (!same(next, this.state)) this.commit(next);
    },

    // Clear zeroes every bar; names and ymax stay.
    clear: function () { this._setAll(0); },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name);
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.variables.length && k !== this.ui.active) {
          this.ui.active = k;
          this.render();
        }
      } else if (name === "align-top") {
        this._setAll(this.state.ymax);
      } else if (name === "align-middle") {
        this._setAll(Math.round(this.state.ymax / 2));
      } else if (name === "align-bottom") {
        this._setAll(0);
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
      var p = this._toBar(ev);
      if (!p.inside) return;
      this._dom.svg.setPointerCapture(ev.pointerId);
      this._stroke = {
        id: ev.pointerId, last: null, start: DCR.deepCopy(this.state.counts)
      };
      this.beginStroke();
      this._paint(p);
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._paint(this._toBar(ev));
    },

    // Set the bar under the pointer to the pointer's (rounded) height; bars
    // skipped since the last event are filled by interpolation. Bars are
    // numbered category by category, variable by variable.
    _paint: function (p) {
      var st = this._stroke, counts = this.state.counts, nv = this.state.variables.length;
      var from = st.last || p, a = from.flat, b = p.flat, d = Math.abs(b - a);
      for (var k = 0; k <= d; k++) {
        var t = d === 0 ? 1 : k / d;
        var f = a + Math.round((b - a) * t);
        var row = counts[f % nv], c = Math.floor(f / nv);
        var room = TOTAL_MAX - (total(counts) - row[c]);   // remaining budget
        row[c] = clamp(Math.round(from.y + (p.y - from.y) * t), 0,
                       Math.min(this.state.ymax, room));
      }
      st.last = { flat: b, y: p.y };
      this.render();
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      try {
        if (!same(this.state.counts, st.start)) this.commit(this.state);
        else this.render();
      } finally {
        this.endStroke();
      }
    },

    // Geometry of one category slot: bars of width bw start `pad` in.
    _slot: function () {
      var L = this._geo, s = this.state;
      var slotW = L.width / s.categories.length;
      var pad = slotW * GROUP_PAD / 2;
      return { w: slotW, pad: pad, bw: (slotW - 2 * pad) / s.variables.length };
    },

    // Pointer -> {flat (bar index), y (continuous count), inside}.
    _toBar: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, s = this.state;
      var x = ev.clientX - r.left, y = ev.clientY - r.top, G = this._slot();
      var nv = s.variables.length, nc = s.categories.length;
      var c = clamp(Math.floor((x - L.left) / G.w), 0, nc - 1);
      var v = clamp(Math.floor((x - L.left - c * G.w - G.pad) / G.bw), 0, nv - 1);
      return {
        flat: c * nv + v,
        y: clamp((L.top + L.height - y) / L.height * s.ymax, 0, s.ymax),
        inside: x >= L.left && x <= L.left + L.width &&
          y >= L.top && y <= L.top + L.height
      };
    },

    // ---- Rendering -----------------------------------------------------------
    _build: function () {
      var self = this, d3 = root.d3, el = this.el;
      var svg = d3.select(el).append("svg");
      var dom = {
        svg: svg.node(),
        frame: svg.append("rect").attr("class", "dcr-frame")
          .attr("fill", "none").attr("stroke", "#c9ced6"),
        yAxis: svg.append("g"),
        xAxis: svg.append("g"),
        yTitle: svg.append("text").attr("text-anchor", "middle").text("count"),
        bars: svg.append("g").style("pointer-events", "none"),
        labels: svg.append("g").style("pointer-events", "none"),
        legend: svg.append("g").style("pointer-events", "none"),
        message: document.createElement("div")
      };
      dom.message.className = "dcr-message";
      dom.message.style.display = "none";
      el.appendChild(dom.message);
      this._dom = dom;
      dom.svg.addEventListener("pointerdown", function (ev) { self._pointerDown(ev); });
      dom.svg.addEventListener("pointermove", function (ev) { self._pointerMove(ev); });
      ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (t) {
        dom.svg.addEventListener(t, function (ev) { self._pointerUp(ev); });
      });
    },

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
      var G = this._slot(), nv = s.variables.length;
      var x = d3.scaleBand().domain(s.categories).range([L.left, L.left + L.width]);
      var y = d3.scaleLinear().domain([0, s.ymax]).range([L.top + L.height, L.top]);

      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).tickValues(y.ticks(Math.max(2, Math.round(L.height / 40)))
          .filter(function (t) { return t === Math.round(t); }))
          .tickFormat(d3.format("d")));
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(x).tickSize(0).tickPadding(8));
      dom.yTitle.attr("transform", "translate(12," + (L.top + L.height / 2) + ") rotate(-90)");

      var act = this.activeIndex();
      dom.bars.selectAll("*").remove();
      dom.labels.selectAll("*").remove();
      dom.legend.selectAll("*").remove();
      var digits = String(Math.max(1, maxCount(s.counts))).length;
      var showLabels = G.bw >= digits * 6 + 2;
      s.categories.forEach(function (cat, c) {
        s.variables.forEach(function (v, i) {
          var n = s.counts[i][c], col = DCR.palette[i % 10], on = i === act && nv > 1;
          var bx = L.left + c * G.w + G.pad + i * G.bw;
          dom.bars.append("rect")
            .attr("x", bx).attr("width", Math.max(0, G.bw - 1))
            .attr("y", y(n)).attr("height", Math.max(0, L.top + L.height - y(n)))
            .attr("fill", col).attr("fill-opacity", on ? 0.85 : 0.6)
            .attr("stroke", col).attr("stroke-width", on ? 2 : 1);
          if (showLabels) {
            dom.labels.append("text").attr("text-anchor", "middle")
              .attr("font-size", 11)
              .attr("x", bx + G.bw / 2).attr("y", y(n) - 3).text(n);
          }
        });
      });

      // Legend: one swatch per variable in the top margin.
      var lx = L.left;
      s.variables.forEach(function (v, i) {
        var g = dom.legend.append("g").attr("transform", "translate(" + lx + ",14)");
        g.append("rect").attr("width", 10).attr("height", 10).attr("y", -9)
          .attr("fill", DCR.palette[i % 10]).attr("fill-opacity", 0.8);
        g.append("text").attr("x", 14).attr("font-size", 12)
          .attr("font-weight", i === act && nv > 1 ? 600 : 400).text(v);
        lx += 14 + v.length * 7 + 14;
      });
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

  DCR.register("count", Count);
})(typeof window !== "undefined" ? window : this);
