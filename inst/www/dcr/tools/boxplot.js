/* Boxplot tool: drag Q1, median and Q3 of one box per variable.
 * Undoable state (this.state, plain JSON):
 *   {variables: [names], family: "normal" | "uniform", n, ylim: [a, b],
 *    q1: [...], q2: [...], q3: [...]}   (one value per variable)
 * Settings (this.ui, not undoable): {active}.
 * The data is a random sample from a two-piece distribution with exactly
 * these quartiles (R/tool_boxplot_spec.R); whiskers are drawn at its 1st and
 * 99th population percentiles. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var FAMILIES = ["normal", "uniform"];
  var MARGIN = { top: 14, right: 16, bottom: 36, left: 52 };
  var GAP = 0.01;        // minimum gap between quartiles, share of diff(ylim)
  var PAD = 0.05;        // ylim expansion beyond a whisker, share of diff(ylim)

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  // Values are rounded relative to the range (a millionth of its order of
  // magnitude), never to a fixed number of significant digits, so an offset
  // range cannot collapse the quartiles.
  function step(ylim) {
    return Math.pow(10, Math.floor(Math.log10(ylim[1] - ylim[0])) - 6);
  }
  function clean(v) { return Number(v.toPrecision(15)); }
  function rnd(v, ylim) { var h = step(ylim); return clean(Math.round(v / h) * h); }
  // Rounded quartiles, unless rounding would break q1 < q2 < q3.
  function roundTriple(q, ylim) {
    var r = q.map(function (v) { return rnd(v, ylim); });
    return r[0] < r[1] && r[1] < r[2] ? r : q;
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

  function cleanN(x) {
    var v = Array.isArray(x) ? NaN : Number(x);
    return x !== null && x !== "" && isFinite(v) && v === Math.round(v) &&
      v >= 1 && v <= 1e6 ? v : null;
  }

  // Standard normal quantile: Acklam's rational approximation
  // (relative error < 1.15e-9).
  var QA = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
            1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00];
  var QB = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
            6.680131188771972e+01, -1.328068155288572e+01];
  var QC = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
            -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00];
  var QD = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
            3.754408661907416e+00];
  function qnorm(p) {
    if (p <= 0) return -Infinity;
    if (p >= 1) return Infinity;
    var q, r, PL = 0.02425;
    if (p < PL) {
      q = Math.sqrt(-2 * Math.log(p));
      return (((((QC[0] * q + QC[1]) * q + QC[2]) * q + QC[3]) * q + QC[4]) * q + QC[5]) /
        ((((QD[0] * q + QD[1]) * q + QD[2]) * q + QD[3]) * q + 1);
    }
    if (p > 1 - PL) {
      q = Math.sqrt(-2 * Math.log(1 - p));
      return -(((((QC[0] * q + QC[1]) * q + QC[2]) * q + QC[3]) * q + QC[4]) * q + QC[5]) /
        ((((QD[0] * q + QD[1]) * q + QD[2]) * q + QD[3]) * q + 1);
    }
    q = p - 0.5;
    r = q * q;
    return (((((QA[0] * r + QA[1]) * r + QA[2]) * r + QA[3]) * r + QA[4]) * r + QA[5]) * q /
      (((((QB[0] * r + QB[1]) * r + QB[2]) * r + QB[3]) * r + QB[4]) * r + 1);
  }

  // Same formulas as R qtwopiece() in R/tool_boxplot_spec.R.
  function qtwopiece(p, q1, q2, q3, family) {
    var d = p < 0.5 ? q2 - q1 : q3 - q2;
    if (family === "normal") return q2 + d / qnorm(0.75) * qnorm(p);
    return q2 + 4 * d * (p - 0.5);
  }

  function whiskers(s, i) {
    return [qtwopiece(0.01, s.q1[i], s.q2[i], s.q3[i], s.family),
            qtwopiece(0.99, s.q1[i], s.q2[i], s.q3[i], s.family)];
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

  var Boxplot = DCR.extend(DCR.Tool, {
    init: function () {
      this.ui = { active: 0 };
    },

    initialState: function (o) {
      var vars = cleanNames(o.variables) || ["V1", "V2", "V3"];
      var ylim = cleanRange(o.ylim) || [0, 10];
      var s = {
        variables: vars,
        family: FAMILIES.indexOf(o.family) >= 0 ? o.family : "normal",
        n: cleanN(o.n) || 100,
        ylim: ylim,
        q1: [], q2: [], q3: []
      };
      vars.forEach(function (v, i) { this._resetBox(s, i); }, this);
      return s;
    },

    // Quartiles at 25 / 50 / 75 % of ylim for variable i.
    _resetBox: function (s, i) {
      var a = s.ylim[0], d = s.ylim[1] - s.ylim[0];
      var r = roundTriple([a + 0.25 * d, a + 0.5 * d, a + 0.75 * d], s.ylim);
      s.q1[i] = r[0]; s.q2[i] = r[1]; s.q3[i] = r[2];
    },

    toSpec: function () {
      var s = this.state, rows = [[], [], []];
      for (var i = 0; i < s.variables.length; i++) {
        var r = roundTriple([s.q1[i], s.q2[i], s.q3[i]], s.ylim);
        for (var c = 0; c < 3; c++) rows[c].push(r[c]);
      }
      return {
        tool: "boxplot",
        family: s.family,
        variables: s.variables.slice(),
        q1: rows[0], q2: rows[1], q3: rows[2],
        ylim: s.ylim.slice(),
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
        family: { value: s.family },
        ylim: { value: s.ylim.slice() }
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
          return cleanN(value);
        case "family":
          return FAMILIES.indexOf(value) >= 0 ? value : null;
        case "ylim":
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
        case "family":
        case "ylim":
          if (!same(v, s[key])) this._commitWith(key, v);
          break;
      }
    },

    _commitWith: function (key, value) {
      var next = DCR.deepCopy(this.state);
      next[key] = value;
      this.commit(next);
    },

    // New variable list: boxes keep their values by name (renames pair in
    // order); new variables get the reset quartiles.
    _setVariables: function (vars) {
      var s = this.state, map = remapVars(s.variables, vars);
      var next = DCR.deepCopy(s);
      next.variables = vars;
      vars.forEach(function (v, j) { this._resetBox(next, j); }, this);
      map.forEach(function (j, i) {
        if (j < 0) return;
        next.q1[j] = s.q1[i];
        next.q2[j] = s.q2[i];
        next.q3[j] = s.q3[i];
      });
      next.q1.length = next.q2.length = next.q3.length = vars.length;
      var act = map[this.activeIndex()];
      this.ui.active = act >= 0 ? act : 0;
      this.commit(next);
    },

    // Widen ylim (in place) so every whisker is visible.
    _expandYlim: function (s) {
      var lo = s.ylim[0], hi = s.ylim[1], pad = PAD * (hi - lo);
      for (var i = 0; i < s.variables.length; i++) {
        var w = whiskers(s, i);
        var h = step(s.ylim);
        if (w[0] < s.ylim[0]) lo = Math.min(lo, clean(Math.floor((w[0] - pad) / h) * h));
        if (w[1] > s.ylim[1]) hi = Math.max(hi, clean(Math.ceil((w[1] + pad) / h) * h));
      }
      s.ylim = [lo, hi];
    },

    clear: function () { this.action("reset"); },

    action: function (name) {
      var m = /^select-(\d+)$/.exec(name), s, next;
      if (m) {
        var k = parseInt(m[1], 10) - 1;
        if (k < this.state.variables.length && k !== this.ui.active) {
          this.ui.active = k;
          this.render();
          this.syncControls();
        }
      } else if (name === "reset") {
        next = DCR.deepCopy(this.state);
        for (var i = 0; i < next.variables.length; i++) this._resetBox(next, i);
        if (!same(next, this.state)) this.commit(next);
      } else if (name === "align") {
        s = this.state;
        next = DCR.deepCopy(s);
        var mid = (s.ylim[0] + s.ylim[1]) / 2;
        for (var j = 0; j < s.variables.length; j++) {
          var d = mid - s.q2[j];
          var r = roundTriple([s.q1[j] + d, mid, s.q3[j] + d], s.ylim);
          next.q1[j] = r[0]; next.q2[j] = r[1]; next.q3[j] = r[2];
        }
        this._expandYlim(next);
        if (!same(next, s)) this.commit(next);
      }
    },

    // ---- Dragging: one gesture = one history entry --------------------------
    _pointerDown: function (ev) {
      if (ev.button !== 0 || this._stroke) return;
      var hit = root.d3.select(ev.target).datum();
      if (!hit || typeof hit.i !== "number") return;
      var s = this.state, i = hit.i;
      this._dom.svg.setPointerCapture(ev.pointerId);
      this._stroke = {
        id: ev.pointerId, i: i, part: hit.part, y0: this._toData(ev),
        start: [s.q1[i], s.q2[i], s.q3[i]]
      };
      this.beginStroke();
      if (this.ui.active !== i) {
        this.ui.active = i;
        this.syncControls();
        this.render();
      }
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      var s = this.state, i = st.i, y = this._toData(ev);
      var lo = s.ylim[0], hi = s.ylim[1];
      // Minimum gap: 1 % of the range, but never more than the box's current
      // gaps, so the order stays strict whatever the range is.
      var g = Math.min(GAP * (hi - lo), st.start[1] - st.start[0], st.start[2] - st.start[1]);
      var q1 = st.start[0], q2 = st.start[1], q3 = st.start[2];
      if (st.part === "q1") {
        q1 = Math.min(q2 - g, Math.max(lo, y));
      } else if (st.part === "q3") {
        q3 = Math.max(q2 + g, Math.min(hi, y));
      } else if (st.part === "q2") {
        q2 = clamp(y, q1 + g, q3 - g);
      } else {
        var d = Math.min(hi - q3, Math.max(lo - q1, y - st.y0));
        q1 += d; q2 += d; q3 += d;
      }
      s.q1[i] = q1; s.q2[i] = q2; s.q3[i] = q3;
      this.render();
    },

    // pointerup, pointercancel and lostpointercapture all end the stroke.
    // ylim expands here (not during the drag), in the same history entry.
    _pointerUp: function (ev) {
      var st = this._stroke;
      if (!st || ev.pointerId !== st.id) return;
      this._stroke = null;
      var s = this.state, i = st.i;
      if (s.q1[i] !== st.start[0] || s.q2[i] !== st.start[1] || s.q3[i] !== st.start[2]) {
        var r = roundTriple([s.q1[i], s.q2[i], s.q3[i]], s.ylim);
        s.q1[i] = r[0]; s.q2[i] = r[1]; s.q3[i] = r[2];
        this._expandYlim(s);
        this.commit(s);
      } else {
        this.render();
      }
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
        clip: svg.append("clipPath").attr("id", "dcr-boxplot-clip").append("rect"),
        plot: svg.append("g").attr("clip-path", "url(#dcr-boxplot-clip)")
      };
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

    _toData: function (ev) {
      var r = this.el.getBoundingClientRect(), L = this._geo, ylim = this.state.ylim;
      return ylim[0] + (L.top + L.height - (ev.clientY - r.top)) / L.height *
        (ylim[1] - ylim[0]);
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
      var k = s.variables.length, band = L.width / k;
      var bw = Math.min(70, band * 0.5);
      var y = d3.scaleLinear().domain(s.ylim).range([L.top + L.height, L.top]);
      var xc = function (i) { return L.left + (i + 0.5) * band; };

      dom.frame.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.clip.attr("x", L.left).attr("y", L.top)
        .attr("width", L.width).attr("height", L.height);
      dom.yAxis.attr("transform", "translate(" + L.left + ",0)")
        .call(d3.axisLeft(y).ticks(Math.max(2, Math.round(L.height / 50))));
      dom.xAxis.attr("transform", "translate(0," + (L.top + L.height) + ")")
        .call(d3.axisBottom(d3.scaleLinear().domain([0, k]).range([L.left, L.left + L.width]))
          .tickValues(s.variables.map(function (v, i) { return i + 0.5; }))
          .tickFormat(function (v) { return s.variables[Math.floor(v)]; })
          .tickSize(0).tickPadding(10));

      var plot = dom.plot;
      plot.selectAll("*").remove();
      s.variables.forEach(function (name, i) {
        var col = DCR.palette[i % 10], x = xc(i), on = i === self.activeIndex();
        var q1 = y(s.q1[i]), q2 = y(s.q2[i]), q3 = y(s.q3[i]);
        var w = whiskers(s, i), wlo = y(w[0]), whi = y(w[1]);
        plot.append("line").attr("x1", x).attr("x2", x).attr("y1", whi).attr("y2", wlo)
          .attr("stroke", col).attr("stroke-width", 1.5);
        [wlo, whi].forEach(function (yy) {
          plot.append("line").attr("x1", x - bw / 4).attr("x2", x + bw / 4)
            .attr("y1", yy).attr("y2", yy).attr("stroke", col).attr("stroke-width", 1.5);
        });
        plot.append("rect").datum({ i: i, part: "body" })
          .attr("x", x - bw / 2).attr("y", q3).attr("width", bw)
          .attr("height", Math.max(0, q1 - q3))
          .attr("fill", col).attr("fill-opacity", on ? 0.45 : 0.3)
          .attr("stroke", col).attr("stroke-width", on ? 2.5 : 1.5)
          .style("cursor", "move");
        plot.append("line").attr("x1", x - bw / 2).attr("x2", x + bw / 2)
          .attr("y1", q2).attr("y2", q2).attr("stroke", col).attr("stroke-width", 3.5)
          .style("pointer-events", "none");
        [["q3", q3], ["q2", q2], ["q1", q1]].forEach(function (h) {
          plot.append("line").datum({ i: i, part: h[0] })
            .attr("x1", x - bw / 2).attr("x2", x + bw / 2)
            .attr("y1", h[1]).attr("y2", h[1])
            .attr("stroke", "transparent").attr("stroke-width", 12)
            .style("cursor", "ns-resize");
          plot.append("circle").attr("cx", x + bw / 2).attr("cy", h[1]).attr("r", 4)
            .attr("fill", "#fff").attr("stroke", col).attr("stroke-width", 1.5)
            .style("pointer-events", "none");
        });
      });
    }
  });

  Boxplot.qnorm = qnorm;
  Boxplot.qtwopiece = qtwopiece;
  DCR.register("boxplot", Boxplot);
})(typeof window !== "undefined" ? window : this);
