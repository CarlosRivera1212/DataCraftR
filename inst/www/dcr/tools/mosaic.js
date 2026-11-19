/* Mosaic tool: draw an exact two-way contingency table. Column widths are the
 * column totals, block heights the row shares inside a column. Drag a vertical
 * border (moves observations between two columns) or a horizontal cut (moves
 * counts between two blocks of one column).
 * Undoable state (this.state, plain JSON):
 *   {cols: [names], rows: [names], names: {col, row},
 *    counts: [[...] per row]}   (rows x cols, integers >= 0)
 * N is not stored: it is always the sum of the counts (>= 1).
 * Settings (this.ui, not undoable): none.
 * Every drag recomputes the table from the snapshot taken when the stroke
 * started, so dragging back restores the start exactly. The pure helpers
 * (allocate, uniform, independent, rescale, dragColumn, dragCut, chisq) are
 * exposed on DCR.tools.mosaic for the V8 checks. */
(function (root) {
  "use strict";

  var DCR = root.DCR;
  var MARGIN = { left: 16, right: 150, top: 16, bottom: 56 };
  var STATS_H = 48;        // px reserved at the bottom for the stats panel
  var HIT = 4;             // half width of a grab area (8 px in all)
  var DEAD_ZONE = 3;       // px: a press that moves less than this is a click
  var N_MAX = 1e6;

  function trim(s) { return String(s).trim(); }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function fill(k, v) {
    var out = [];
    for (var i = 0; i < k; i++) out.push(v);
    return out;
  }
  function copy(m) { return m.map(function (r) { return r.slice(); }); }

  // Valid category names, trimmed like R's check_names(): 2 to 10, or null.
  function cleanNames(x) {
    var out = DCR.asArray(x).map(trim);
    if (out.length < 2 || out.length > 10) return null;
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

  // {col, row}: two non-empty, distinct names, or null.
  function cleanVarNames(x) {
    if (!x || typeof x !== "object") return null;
    var v = cleanNames([x.col, x.row].map(function (s) { return s == null ? "" : s; }));
    return v ? { col: v[0], row: v[1] } : null;
  }

  // Map old category indices to new ones: names present in both are kept;
  // with the same number of categories the rest are renames (paired in order).
  function remap(oldNames, newNames) {
    var map = oldNames.map(function (g) { return newNames.indexOf(g); });
    if (oldNames.length === newNames.length) {
      var free = newNames.map(function (g, j) { return j; })
        .filter(function (j) { return map.indexOf(j) < 0; });
      map = map.map(function (j) { return j >= 0 ? j : free.shift(); });
    }
    return map;
  }

  // "N observations of a, b removed - Ctrl+Z to undo" for removed categories
  // (old index i with map[i] < 0) whose counts sumOf(i) are not zero.
  function removedMessage(names, map, sumOf) {
    var n = 0, gone = [];
    names.forEach(function (g, i) {
      var k = map[i] < 0 ? sumOf(i) : 0;
      if (k > 0) { n += k; gone.push(g); }
    });
    if (!gone.length) return null;
    return n + (n === 1 ? " observation" : " observations") + " of " +
      gone.join(", ") + " removed " + String.fromCharCode(8212) + " Ctrl+Z to undo";
  }

  // ---- Pure table maths (no DOM) --------------------------------------------
  function sum(a) { return a.reduce(function (s, v) { return s + v; }, 0); }
  function colTotal(m, c) {
    var t = 0;
    for (var r = 0; r < m.length; r++) t += m[r][c];
    return t;
  }
  function colTotals(m) {
    return m[0].map(function (v, c) { return colTotal(m, c); });
  }
  function rowTotals(m) { return m.map(sum); }
  function grand(m) { return sum(rowTotals(m)); }
  function column(m, c) { return m.map(function (row) { return row[c]; }); }

  // Largest-remainder split of the whole number `total` over non-negative
  // whole weights. All weights 0: an even split. Exact integer arithmetic;
  // remainder ties go to the earlier index.
  function allocate(total, weights) {
    var n = weights.length, w = weights, s = sum(w), i;
    if (!(s > 0)) { w = fill(n, 1); s = n; }
    var out = [], rem = [], used = 0;
    for (i = 0; i < n; i++) {
      var num = w[i] * total, r = num % s;
      out.push((num - r) / s);
      rem.push(r);
      used += out[i];
    }
    var order = rem.map(function (r, k) { return k; }).sort(function (a, b) {
      return rem[b] - rem[a] || a - b;
    });
    for (var k = 0; k < total - used; k++) out[order[k % n]]++;
    return out;
  }

  function unflat(flat, nr, nc) {
    var m = [];
    for (var r = 0; r < nr; r++) m.push(flat.slice(r * nc, (r + 1) * nc));
    return m;
  }

  function uniform(nr, nc, N) { return unflat(allocate(N, fill(nr * nc, 1)), nr, nc); }

  // Rescale every cell to a table summing to N (zeros stay zero; an all-zero
  // table becomes uniform).
  function rescale(counts, N) {
    var nr = counts.length, nc = counts[0].length;
    return unflat(allocate(N, [].concat.apply([], counts)), nr, nc);
  }

  // Cell = rowTotal x colTotal / N by largest remainder, preserving both
  // margins exactly.
  function independent(counts) {
    var nr = counts.length, nc = counts[0].length, N = grand(counts);
    var rt = rowTotals(counts), ct = colTotals(counts);
    var m = [], cells = [], rdef = rt.slice(), cdef = ct.slice(), left = 0, r, c;
    for (r = 0; r < nr; r++) {
      m.push([]);
      for (c = 0; c < nc; c++) {
        var num = rt[r] * ct[c], rem = num % N, f = (num - rem) / N;
        m[r][c] = f;
        rdef[r] -= f;
        cdef[c] -= f;
        cells.push({ r: r, c: c, rem: rem, k: r * nc + c });
      }
    }
    cells.sort(function (a, b) { return b.rem - a.rem || a.k - b.k; });
    left = sum(rdef);
    while (left > 0) {                    // each pass places at least one
      for (var i = 0; i < cells.length && left > 0; i++) {
        var q = cells[i];
        if (rdef[q.r] > 0 && cdef[q.c] > 0) {
          m[q.r][q.c]++; rdef[q.r]--; cdef[q.c]--; left--;
        }
      }
    }
    return m;
  }

  // Move `delta` observations from column j+1 to column j (negative: the
  // other way), clamped so neither total goes below 0. Each of the two
  // columns gets its new total split like its start column (largest
  // remainder; an empty start column is split evenly).
  function dragColumn(start, j, delta) {
    var a0 = colTotal(start, j), b0 = colTotal(start, j + 1), T = a0 + b0;
    var na = clamp(a0 + Math.round(delta), 0, T);
    var newA = allocate(na, column(start, j));
    var newB = allocate(T - na, column(start, j + 1));
    var out = copy(start);
    for (var r = 0; r < out.length; r++) {
      out[r][j] = newA[r];
      out[r][j + 1] = newB[r];
    }
    return out;
  }

  // Move `delta` observations from row i+1 to row i inside column j, clamped.
  function dragCut(start, j, i, delta) {
    var s0 = start[i][j], S = s0 + start[i + 1][j];
    var out = copy(start);
    out[i][j] = clamp(s0 + Math.round(delta), 0, S);
    out[i + 1][j] = S - out[i][j];
    return out;
  }

  // Upper regularised incomplete gamma Q(a, x) (Numerical Recipes).
  function lgamma(x) {
    var g = [676.5203681218851, -1259.1392167224028, 771.32342877765313,
             -176.61502916214059, 12.507343278686905, -0.13857109526572012,
             9.9843695780195716e-6, 1.5056327351493116e-7];
    if (x < 0.5) return Math.log(Math.PI / Math.sin(Math.PI * x)) - lgamma(1 - x);
    x -= 1;
    var a = 0.99999999999980993, t = x + 7.5;
    for (var i = 0; i < 8; i++) a += g[i] / (x + i + 1);
    return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
  }
  function gammaQ(a, x) {
    if (x <= 0) return 1;
    var gln = lgamma(a), i;
    if (x < a + 1) {
      var ap = a, del = 1 / a, s = del;
      for (i = 0; i < 1000; i++) {
        ap++; del *= x / ap; s += del;
        if (Math.abs(del) < Math.abs(s) * 1e-15) break;
      }
      return clamp(1 - s * Math.exp(-x + a * Math.log(x) - gln), 0, 1);
    }
    var b = x + 1 - a, c = 1e300, d = 1 / b, h = d;
    for (i = 1; i < 1000; i++) {
      var an = -i * (i - a);
      b += 2;
      d = an * d + b; if (Math.abs(d) < 1e-300) d = 1e-300;
      c = b + an / c; if (Math.abs(c) < 1e-300) c = 1e-300;
      d = 1 / d;
      var dl = d * c;
      h *= dl;
      if (Math.abs(dl - 1) < 1e-15) break;
    }
    return clamp(Math.exp(-x + a * Math.log(x) - gln) * h, 0, 1);
  }

  // Plain Pearson chi-square (no continuity correction) of the table, with
  // df from the non-empty rows and columns. Undefined values are null; or and
  // rr (2 x 2 only) compare the second row's second column with the first:
  // odds ratio (a d) / (b c) and relative risk (a / col1) / (b / col0) for
  // a = counts[1][1], b = counts[1][0], c = counts[0][1], d = counts[0][0].
  function chisq(counts) {
    var nr = counts.length, nc = counts[0].length, N = grand(counts);
    var rt = rowTotals(counts), ct = colTotals(counts), r, c;
    var nzr = rt.filter(function (v) { return v > 0; }).length;
    var nzc = ct.filter(function (v) { return v > 0; }).length;
    var stat = 0, low = 0;
    for (r = 0; r < nr; r++) {
      for (c = 0; c < nc; c++) {
        var e = rt[r] * ct[c] / N;
        if (e > 0) {
          stat += Math.pow(counts[r][c] - e, 2) / e;
          if (e < 5) low++;
        }
      }
    }
    var df = (nzr - 1) * (nzc - 1);
    var out = {
      stat: stat, df: df, expectedLow: low, or: null, rr: null,
      p: df > 0 ? gammaQ(df / 2, stat / 2) : null,
      v: df > 0 ? Math.sqrt(stat / (N * Math.min(nzr - 1, nzc - 1))) : null
    };
    if (nr === 2 && nc === 2) {
      var a = counts[1][1], b = counts[1][0], cc = counts[0][1], d = counts[0][0];
      if (b * cc > 0) out.or = (a * d) / (b * cc);
      if (ct[0] > 0 && ct[1] > 0 && b > 0) out.rr = (a / ct[1]) / (b / ct[0]);
    }
    return out;
  }

  var Mosaic = DCR.extend(DCR.Tool, {
    initialState: function (o) {
      var cols = cleanNames(o.cols) || ["No", "Yes"];
      var rows = cleanNames(o.rows) || ["Healthy", "Sick"];
      var n = cleanWhole(o.n, 1, N_MAX) || 200;
      return {
        cols: cols, rows: rows,
        names: cleanVarNames(o.names) || { col: "exposure", row: "outcome" },
        counts: uniform(rows.length, cols.length, n)
      };
    },

    toSpec: function () {
      var s = this.state;
      return {
        tool: "mosaic",
        cols: s.cols.slice(), rows: s.rows.slice(),
        names: { col: s.names.col, row: s.names.row },
        counts: copy(s.counts)
      };
    },

    controls: function () {
      var s = this.state;
      return {
        cols: { value: s.cols.join(", ") },
        rows: { value: s.rows.join(", ") },
        n: { value: grand(s.counts) },
        names: { value: { col: s.names.col, row: s.names.row } }
      };
    },

    controlValue: function (key, value) {
      switch (key) {
        case "cols":
        case "rows":
          return cleanNames(typeof value === "string" ? value.split(",") : value);
        case "n":
          return cleanWhole(value, 1, N_MAX);
        case "names":
          return cleanVarNames(value);
      }
      return null;
    },

    setControl: function (key, value) {
      var s = this.state, v = this.controlValue(key, value);
      if (v === null) return;
      switch (key) {
        case "cols":
          if (!same(v, s.cols)) this._setCategories("cols", v);
          break;
        case "rows":
          if (!same(v, s.rows)) this._setCategories("rows", v);
          break;
        case "n":
          if (v !== grand(s.counts)) this._commitCounts(rescale(s.counts, v));
          break;
        case "names":
          if (!same(v, s.names)) this._commitWith({ names: v });
          break;
      }
    },

    _commitWith: function (patch) {
      var next = DCR.deepCopy(this.state);
      for (var k in patch) next[k] = patch[k];
      this.commit(next);
    },

    // New counts (same categories); no history entry if nothing changes.
    _commitCounts: function (counts) {
      if (same(counts, this.state.counts)) return;
      this._commitWith({ counts: counts });
    },

    // New category list for "cols" or "rows": counts keep their values by
    // name (renames pair in order); new categories start at 0; removed ones
    // take their counts with them (a table left empty becomes uniform again
    // with the old N).
    _setCategories: function (which, names) {
      var s = this.state, map = remap(s[which], names);
      var cols = which === "cols" ? names : s.cols;
      var rows = which === "rows" ? names : s.rows;
      var mr = which === "rows" ? map : s.rows.map(function (g, i) { return i; });
      var mc = which === "cols" ? map : s.cols.map(function (g, j) { return j; });
      var counts = rows.map(function () { return fill(cols.length, 0); });
      s.counts.forEach(function (row, i) {
        row.forEach(function (n, j) {
          if (mr[i] >= 0 && mc[j] >= 0) counts[mr[i]][mc[j]] = n;
        });
      });
      var msg = removedMessage(s[which], map, function (k) {
        return which === "rows" ? sum(s.counts[k]) : colTotal(s.counts, k);
      });
      if (grand(counts) < 1) counts = uniform(rows.length, cols.length, grand(s.counts));
      var patch = { counts: counts };
      patch[which] = names;
      this._commitWith(patch);
      if (msg) this._flash(msg);
    },

    // Clear = Uniform with the current categories and N.
    clear: function () { this._uniform(); },

    _uniform: function () {
      var s = this.state;
      this._commitCounts(uniform(s.rows.length, s.cols.length, grand(s.counts)));
    },

    action: function (name) {
      if (name === "independent") this._commitCounts(independent(this.state.counts));
      else if (name === "uniform") this._uniform();
    },

    // ---- Geometry and hit testing -------------------------------------------
    // x of every column border: bx[0] = left edge ... bx[nc] = right edge.
    _borders: function (counts, geo) {
      var N = grand(counts), acc = 0, bx = [geo.x0];
      colTotals(counts).forEach(function (t) {
        acc += t;
        bx.push(geo.x0 + acc / N * geo.w);
      });
      return bx;
    },

    // y of the cut below row i in column c.
    _cutY: function (counts, geo, c, i) {
      var ct = colTotal(counts, c), acc = 0;
      for (var k = 0; k <= i; k++) acc += counts[k][c];
      return geo.y0 + (ct > 0 ? acc / ct : 0) * geo.h;
    },

    // Nearest borders to the pointer (all of them when several coincide) as
    // {kind: "v"|"h", list: [{idx, col, pos}]}, or null. Vertical borders win.
    _hitTest: function (px, py) {
      var geo = this._geo, counts = this.state.counts, bx = this._borders(counts, geo);
      var nc = counts[0].length, nr = counts.length, c, i, cands = [], d;
      function nearest(list) {
        if (!list.length) return null;
        var best = Math.min.apply(null, list.map(function (q) { return q.dist; }));
        return list.filter(function (q) { return q.dist <= best + 0.5; });
      }
      if (py >= geo.y0 - HIT && py <= geo.y0 + geo.h + HIT) {
        for (c = 1; c < nc; c++) {
          d = Math.abs(px - bx[c]);
          if (d <= HIT) cands.push({ idx: c - 1, col: c - 1, pos: bx[c], dist: d });
        }
        var v = nearest(cands);
        if (v) return { kind: "v", list: v };
      }
      for (c = 0; c < nc; c++) {
        if (px < bx[c] || px > bx[c + 1] || bx[c + 1] - bx[c] < 1) continue;
        if (colTotal(counts, c) === 0) continue;
        cands = [];
        for (i = 0; i < nr - 1; i++) {
          var y = this._cutY(counts, geo, c, i);
          d = Math.abs(py - y);
          if (d <= HIT) cands.push({ idx: i, col: c, pos: y, dist: d });
        }
        var h = nearest(cands);
        if (h) return { kind: "h", list: h };
      }
      return null;
    },

    _hitKey: function (h) {
      return h ? h.kind + h.list.map(function (q) { return q.col + "_" + q.idx; }).join("|") : "";
    },

    _local: function (ev) {
      var r = this.el.getBoundingClientRect();
      return { x: ev.clientX - r.left, y: ev.clientY - r.top };
    },

    // ---- Strokes: one drag = one history entry ---------------------------------
    _pointerDown: function (ev) {
      if (ev.button !== 0 || !this._geo) return;
      if (this._stroke) {
        // a stroke whose end event never came (lost capture): finish it first
        var old = this._stroke, svg = this._dom.svg;
        var held = typeof svg.hasPointerCapture === "function" && svg.hasPointerCapture(old.id);
        if (ev.pointerId !== old.id && held) return;
        this._pointerUp({ pointerId: old.id });
      }
      var p = this._local(ev), hit = this._hitTest(p.x, p.y);
      if (!hit) return;
      if (typeof ev.preventDefault === "function") ev.preventDefault();
      this._dom.svg.setPointerCapture(ev.pointerId);
      this._stroke = {
        id: ev.pointerId, hit: hit, cand: hit.list.length === 1 ? hit.list[0] : null,
        cx: ev.clientX, cy: ev.clientY, moved: false, geo: copyGeo(this._geo),
        start: copy(this.state.counts)
      };
      this.beginStroke();
      this._requestDraw();
    },

    _pointerMove: function (ev) {
      var st = this._stroke;
      if (!st) {
        if (!this._geo || !this._dom) return;
        var p = this._local(ev), h = this._hitTest(p.x, p.y);
        if (this._hitKey(h) !== this._hitKey(this._hover)) {
          this._hover = h;
          this._requestDraw();
        }
        return;
      }
      if (ev.pointerId !== st.id) return;
      var dx = ev.clientX - st.cx, dy = ev.clientY - st.cy;
      if (!st.moved && Math.hypot(dx, dy) >= DEAD_ZONE) {
        st.moved = true;
        if (!st.cand) {
          // coincident borders: the one on the side the pointer moves toward
          var list = st.hit.list, back = (st.hit.kind === "v" ? dx : dy) < 0;
          st.cand = back ? list[0] : list[list.length - 1];
        }
      }
      if (!st.moved) return;
      // always from the stroke-start snapshot: dragging back restores it
      var c = st.cand, start = st.start, N = grand(start);
      if (st.hit.kind === "v") {
        this.state.counts = dragColumn(start, c.idx, dx / st.geo.w * N);
      } else {
        this.state.counts = dragCut(start, c.col, c.idx,
                                    dy / st.geo.h * colTotal(start, c.col));
      }
      this._requestDraw();
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

    // ---- Rendering -----------------------------------------------------------
    _build: function () {
      var self = this, el = this.el;
      var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      el.appendChild(svg);
      var stats = document.createElement("div");
      stats.className = "dcr-mosaic-stats";
      stats.style.cssText = "position:absolute;left:0;right:0;bottom:0;height:" + STATS_H +
        "px;box-sizing:border-box;padding:4px 14px;overflow-y:auto;background:#fff;" +
        "border-top:1px solid #dfe3e8;font-size:12px;display:flex;flex-wrap:wrap;" +
        "gap:2px 18px;align-content:flex-start;pointer-events:none;";
      el.appendChild(stats);
      var msg = document.createElement("div");
      msg.className = "dcr-message";
      msg.style.display = "none";
      el.appendChild(msg);
      this._dom = { svg: svg, stats: stats, message: msg };
      svg.addEventListener("pointerdown", function (ev) { self._pointerDown(ev); });
      svg.addEventListener("pointermove", function (ev) { self._pointerMove(ev); });
      svg.addEventListener("pointerleave", function () {
        if (!self._stroke && self._hover) { self._hover = null; self._requestDraw(); }
      });
      ["pointerup", "pointercancel", "lostpointercapture"].forEach(function (t) {
        svg.addEventListener(t, function (ev) { self._pointerUp(ev); });
      });
    },

    render: function () {
      var W = this.el.clientWidth, H = this.el.clientHeight;
      if (!W || !H) return;
      if (!this._dom) this._build();
      var w = Math.max(40, W - MARGIN.left - MARGIN.right);
      var h = Math.max(40, H - MARGIN.top - MARGIN.bottom - STATS_H);
      this._geo = { x0: MARGIN.left, y0: MARGIN.top, w: w, h: h };
      this._draw();
    },

    // Redraw at most once per frame.
    _requestDraw: function () {
      if (!this._dom || !this._geo || this._frame) return;
      var self = this;
      if (typeof root.requestAnimationFrame !== "function") { this._draw(); return; }
      this._frame = root.requestAnimationFrame(function () {
        self._frame = null;
        self._draw();
      });
    },

    _draw: function () {
      var dom = this._dom, geo = this._geo;
      if (!dom || !geo || !dom.stats) return;
      var s = this.state, counts = s.counts, N = grand(counts);
      var nr = s.rows.length, nc = s.cols.length, bx = this._borders(counts, geo);
      var svg = dom.svg, c, r, y1 = geo.y0 + geo.h;
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      var cts = colTotals(counts);
      for (c = 0; c < nc; c++) {
        var xl = bx[c], xr = bx[c + 1], cw = xr - xl, ct = cts[c], acc = 0;
        if (ct > 0 && cw > 0) {
          for (r = 0; r < nr; r++) {
            var n = counts[r][c], ya = geo.y0 + acc / ct * geo.h;
            acc += n;
            var yb = geo.y0 + acc / ct * geo.h, bh = yb - ya;
            if (n === 0) continue;
            svg.appendChild(svgEl("rect", { x: xl, y: ya, width: cw, height: bh,
              fill: DCR.palette[r % 10], stroke: "#fff", "stroke-width": 1.5 }));
            if (bh >= 15 && cw >= 26) {
              var cx = xl + cw / 2, cy = (ya + yb) / 2, big = bh >= 32 && cw >= 44;
              svg.appendChild(svgEl("text", labelAttrs(cx, big ? cy - 1 : cy + 4, 13, 600), n));
              if (big) {
                svg.appendChild(svgEl("text", labelAttrs(cx, cy + 13, 10, 400),
                                      (n / N * 100).toFixed(1) + "%"));
              }
            }
          }
        }
        var mid = (xl + xr) / 2;
        if (cw >= 14) {
          svg.appendChild(svgEl("text", { x: mid, y: y1 + 18, "text-anchor": "middle",
            "font-size": 12, "font-weight": 600, fill: "#1f2933" },
            fit(s.cols[c], Math.max(cw, 30), 12)));
          svg.appendChild(svgEl("text", { x: mid, y: y1 + 33, "text-anchor": "middle",
            "font-size": 11, fill: "#6b7785" }, "n=" + ct));
        } else if (ct === 0) {
          svg.appendChild(svgEl("text", { x: mid, y: y1 + 18 + 15 * (c % 3),
            "text-anchor": "middle", "font-size": 10, fill: "#9aa5b1" },
            fit(s.cols[c], 60, 10) + " (0)"));
        }
      }
      var rt = rowTotals(counts), lx = geo.x0 + geo.w + 18;
      for (r = 0; r < nr; r++) {
        var ly = geo.y0 + r * 20;
        svg.appendChild(svgEl("rect", { x: lx, y: ly, width: 12, height: 12, rx: 2,
          fill: DCR.palette[r % 10] }));
        svg.appendChild(svgEl("text", { x: lx + 18, y: ly + 10.5, "font-size": 12, fill: "#1f2933" },
          fit(s.rows[r], MARGIN.right - 40, 12) + " (" + rt[r] + ")"));
      }
      var st = this._stroke, act = this._hover;
      if (st) act = st.cand ? { kind: st.hit.kind, list: [st.cand] } : st.hit;
      if (act) this._drawHandle(svg, act, bx);
      svg.appendChild(svgEl("rect", { x: geo.x0, y: geo.y0, width: geo.w, height: geo.h,
        fill: "none", stroke: "#c9ced6", "pointer-events": "none" }));
      svg.style.cursor = act ? (act.kind === "v" ? "ew-resize" : "ns-resize") : "default";
      this._drawStats();
    },

    _drawHandle: function (svg, act, bx) {
      var geo = this._geo, q = act.list[0], a;
      if (act.kind === "v") {
        var x = bx[q.idx + 1];
        a = { x1: x, x2: x, y1: geo.y0 - 4, y2: geo.y0 + geo.h + 4 };
      } else {
        var y = this._cutY(this.state.counts, geo, q.col, q.idx);
        a = { x1: bx[q.col], x2: bx[q.col + 1], y1: y, y2: y };
      }
      a.stroke = "#1f2933"; a["stroke-width"] = 3; a["stroke-linecap"] = "round";
      a["pointer-events"] = "none";
      svg.appendChild(svgEl("line", a));
    },

    // Chi-square panel in the canvas area (text only, no HTML from names).
    _drawStats: function () {
      var panel = this._dom.stats, s = this.state, q = chisq(s.counts);
      function f(x, d) { return x === null || !isFinite(x) ? "n/a" : x.toFixed(d); }
      var items = [
        ["Chi-square", f(q.stat, 3)],
        ["df", q.df > 0 ? String(q.df) : "n/a"],
        ["p-value", q.p === null ? "n/a" : (q.p < 0.0001 ? "< 0.0001" : q.p.toFixed(4))],
        ["Cramer's V", f(q.v, 3)]
      ];
      if (s.rows.length === 2 && s.cols.length === 2) {
        var cmp = " (" + s.rows[1] + ": " + s.cols[1] + " vs " + s.cols[0] + ")";
        items.push(["Odds ratio" + cmp, f(q.or, 3)]);
        items.push(["Relative risk" + cmp, f(q.rr, 3)]);
      }
      if (q.expectedLow > 0) {
        items.push([null, "expected < 5 in " + q.expectedLow +
                          (q.expectedLow === 1 ? " cell" : " cells")]);
      }
      while (panel.firstChild) panel.removeChild(panel.firstChild);
      items.forEach(function (it) {
        var span = document.createElement("span");
        span.style.whiteSpace = "nowrap";
        if (it[0] !== null) span.appendChild(document.createTextNode(it[0] + " "));
        var b = document.createElement("b");
        b.textContent = it[1];
        span.appendChild(b);
        panel.appendChild(span);
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

  function copyGeo(g) { return { x0: g.x0, y0: g.y0, w: g.w, h: g.h }; }

  function svgEl(name, attrs, text) {
    var e = document.createElementNS("http://www.w3.org/2000/svg", name);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function labelAttrs(x, y, size, weight) {
    return { x: x, y: y, "text-anchor": "middle", fill: "#fff", "font-size": size,
      "font-weight": weight, "pointer-events": "none",
      style: "paint-order:stroke;stroke:rgba(0,0,0,.35);stroke-width:2px" };
  }

  // Shorten a label to about px pixels.
  function fit(text, px, size) {
    var mx = Math.floor(px / (size * 0.58));
    return text.length <= mx ? text : (mx > 2 ? text.slice(0, mx - 1) + ".." : "");
  }

  Mosaic.allocate = allocate;
  Mosaic.uniform = uniform;
  Mosaic.independent = independent;
  Mosaic.rescale = rescale;
  Mosaic.dragColumn = dragColumn;
  Mosaic.dragCut = dragCut;
  Mosaic.chisq = chisq;

  DCR.register("mosaic", Mosaic);
})(typeof window !== "undefined" ? window : this);
