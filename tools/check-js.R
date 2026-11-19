# Syntax-check every JavaScript file under inst/www/dcr/, then run
# behavioural checks of DOM-free logic (DCR.History, tool state) in V8.
# Run from the package root: Rscript tools/check-js.R
files <- list.files("inst/www/dcr", pattern = "[.]js$", recursive = TRUE,
                    full.names = TRUE)
read_src <- function(f) {
  paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
ctx <- V8::v8()
failed <- FALSE
for (f in files) {
  src <- read_src(f)
  ok <- tryCatch({
    ctx$eval(sprintf("new Function(%s)", jsonlite::toJSON(src, auto_unbox = TRUE)))
    TRUE
  }, error = function(e) {
    message("JS syntax error in ", f, ": ", conditionMessage(e))
    FALSE
  })
  if (!ok) failed <- TRUE
}
if (failed) quit(status = 1)

# A V8 context with core.js and the given tool scripts loaded.
engine <- function(tools = character()) {
  cx <- V8::v8()
  cx$eval("var window = this;")
  cx$eval(read_src("inst/www/dcr/core.js"))
  for (t in tools) cx$eval(read_src(file.path("inst/www/dcr/tools", paste0(t, ".js"))))
  cx
}

# Each check is JS returning an array of booleans; all must be true.
run_check <- function(label, cx, code) {
  res <- cx$eval(code)
  if (!all(strsplit(res, ",", fixed = TRUE)[[1]] == "true")) {
    message(label, " check failed: ", res)
    quit(status = 1)
  }
}

# History: push 3 states, undo twice -> state 1; redo -> state 2;
# push after undo clears redo.
run_check("DCR.History", engine(), "
  (function () {
    var h = new DCR.History({v: 0});
    h.push({v: 1}); h.push({v: 2}); h.push({v: 3});
    h.undo(); h.undo();
    var ok1 = h.state.v === 1 && h.canRedo;
    h.redo();
    var ok2 = h.state.v === 2;
    h.undo();
    h.push({v: 9});
    var ok3 = h.state.v === 9 && !h.canRedo && h.canUndo;
    var s = h.state; s.v = 100;
    var ok4 = h.state.v === 9;
    return [ok1, ok2, ok3, ok4].join(',');
  })()
")

# History size budget (sizeOf/budget) on top of the 200-entry cap.
run_check("History budget", engine(), "
  (function () {
    var ok = [];
    var h = new DCR.History({n: 1}, {sizeOf: function (s) { return s.n; }, budget: 10});
    h.push({n: 4}); h.push({n: 4});
    ok.push(h.length === 3);
    h.push({n: 4});
    ok.push(h.length === 2 && h.state.n === 4 && h.canUndo);
    h.push({n: 50});
    ok.push(h.length === 1 && h.state.n === 50 && !h.canUndo);
    var c = new DCR.History({v: 0});
    for (var i = 1; i <= 250; i++) c.push({v: i});
    ok.push(c.length === 200 && c.state.v === 250);
    return ok.join(',');
  })()
")

# EchoGuard: echoes (in order) are dropped once; other values are real.
run_check("EchoGuard", engine(), "
  (function () {
    var g = new DCR.EchoGuard(), ok = [];
    g.pushed('k', 1); g.pushed('k', 0);
    ok.push(g.isEcho('k', 1) === true);
    ok.push(g.isEcho('k', 0) === true);
    ok.push(g.isEcho('k', 0) === false);
    g.pushed('k', [1, 2]); g.pushed('k', [3, 4]);
    ok.push(g.isEcho('k', [3, 4]) === true);   // first echo deduped by Shiny
    ok.push(g.isEcho('k', [1, 2]) === false);  // older pending dropped
    g.pushed('k', 5);
    ok.push(g.isEcho('k', 6) === false && g.isEcho('k', 5) === false);
    ok.push(g.isEcho('other', 5) === false);
    return ok.join(',');
  })()
")

# EchoGuard expiry: pushes that never echo (Shiny dedup) stop matching after
# the ttl, so a later identical user value is applied.
run_check("EchoGuard expiry", engine("scatter"), "
  (function () {
    var clock = 0, now = function () { return clock; }, ok = [];
    var g = new DCR.EchoGuard({ttl: 2000, now: now});
    g.pushed('k', 'G0'); g.pushed('k', 'G1');
    clock = 1500;
    ok.push(g.isEcho('k', 'G1') === true);            // within ttl: echo
    g.pushed('k', 'G0'); g.pushed('k', 'G1');
    clock = 4000;
    ok.push(g.isEcho('k', 'G0') === false);           // expired: real input
    // the same scenario through a scatter tool
    var t = new DCR.tools.scatter({clientWidth: 0, clientHeight: 0},
                                  {groups: ['A', 'B', 'C']});
    t._flash = function () {};
    t._echo = new DCR.EchoGuard({now: now});
    t.receiveControl('groups', ['A', 'B']);          // user: G1
    t.undo(); t.markPushed('groups', 'A, B, C');      // push G0
    t.redo(); t.markPushed('groups', 'A, B');         // push G1 = last sent: no echo
    clock += 2500;
    var n = t.history.length;
    t.receiveControl('groups', ['A', 'B', 'C']);     // user types G0 again
    ok.push(t.history.length === n + 1 && t.state.groups.join() === 'A,B,C');
    return ok.join(',');
  })()
")

# Base Tool: during a stroke, controls/undo/redo/run are queued and applied
# after the stroke is committed.
run_check("Tool stroke queue", engine(), "
  (function () {
    var T = DCR.extend(DCR.Tool, {
      initialState: function () { return {v: 0, k: 'a'}; },
      setControl: function (key, value) {
        if (value !== this.state[key]) {
          var s = DCR.deepCopy(this.state); s[key] = value; this.commit(s);
        }
      }
    });
    var t = new T({clientWidth: 0, clientHeight: 0}, {}), ok = [];
    t.beginStroke();
    t.receiveControl('k', 'b');
    t.undo();
    t.run('redo');
    ok.push(t.state.k === 'a' && t.history.length === 1);
    t.state.v = 1; t.commit(t.state);        // the stroke's own entry
    t.endStroke();
    // stroke, then k = b, then undo (back to the stroke), then redo
    ok.push(t.history.length === 3 && t.state.v === 1 && t.state.k === 'b');
    t.undo();
    ok.push(t.state.v === 1 && t.state.k === 'a');
    t.undo();
    ok.push(t.state.v === 0);
    return ok.join(',');
  })()
")

# Scatter state logic without a DOM (render() is a no-op at size 0).
run_check("Scatter", engine("scatter"), "
  (function () {
    var el = {clientWidth: 0, clientHeight: 0};
    var S = DCR.tools.scatter, ok = [];
    // scalar-or-array options (jsonlite auto_unbox), names trimmed like R
    var t = new S(el, {groups: ' A ', xlim: [-5, 5], ylim: [0, 1]});
    ok.push(JSON.stringify(t.state.groups) === '[\"A\"]');
    t = new S(el, {groups: ['A', 'B', 'C'], xlim: [0, 10], ylim: [0, 10]});
    var msgs = [], synced = null;
    t._flash = function (m) { msgs.push(m); };
    t.onControls(function (c) { synced = c; });
    // spray: inside the disc (r = brush * diff(xlim)) and inside the ranges
    var n = t._spray(0.5, 5, 2000);
    var p = t.state.points, inDisc = true;
    for (var i = 0; i < p.x.length; i++) {
      var d = Math.sqrt(Math.pow(p.x[i] - 0.5, 2) + Math.pow(p.y[i] - 5, 2));
      if (d > 0.8 + 1e-9 || p.x[i] < 0) inDisc = false;
    }
    ok.push(n > 1000 && n < 2000 && n === p.x.length && inDisc);
    t.commit(t.state);
    t.action('select-2');
    ok.push(synced.active.value === '2');
    t._spray(5, 5, 10); t.commit(t.state);
    var spec = t.toSpec();
    ok.push(spec.tool === 'scatter' && spec.points.group.length === n + 10 &&
            spec.points.group[n] === 'B' && spec.points.group[0] === 'A');
    // rounded to 1e-6 (a millionth of the order of magnitude of xlim = 0..10)
    ok.push(spec.points.x.every(function (v) {
      return Math.abs(v * 1e6 - Math.round(v * 1e6)) < 1e-6;
    }) && Math.abs(spec.points.x[0] - t.state.points.x[0]) <= 5e-7);
    // rename keeps points and relabels them
    t.setControl('groups', 'A, X, C'.split(','));
    ok.push(t.toSpec().points.group[n] === 'X' && t.toSpec().points.x.length === n + 10);
    // remove a group with points: one undoable step, others kept, message
    var depth = t.history._index;
    t.setControl('groups', ['A', 'C']);
    ok.push(t.state.points.x.length === n && t.history._index === depth + 1 &&
            msgs[0] === '10 points of X removed \\u2014 Ctrl+Z to undo' &&
            synced.groups.value === 'A, C' && synced.active.choices.length === 2);
    t.undo();
    ok.push(t.state.points.x.length === n + 10 && t.state.groups[1] === 'X');
    // reorder keeps each point with its group name
    t.setControl('groups', ['C', 'X', 'A']);
    ok.push(t.toSpec().points.group[0] === 'A' && t.toSpec().points.group[n] === 'X');
    t.undo();
    // invalid and unchanged values change nothing (no history entry)
    depth = t.history._index;
    t.setControl('xlim', [5, 5]);
    t.setControl('ylim', [10, 0]);
    t.setControl('groups', ['A', 'A']);
    t.setControl('groups', ['A', ' ']);
    t.setControl('names', {x: 'a', y: 'a', group: 'g'});
    t.setControl('xlim', [0, 10]);
    t.setControl('groups', [' A', 'X ', 'C']);
    t.setControl('brush', 0.9);
    ok.push(t.history._index === depth && t.ui.brush === 0.08);
    // ranges change the view, never the data
    var x0 = t.state.points.x[0];
    t.setControl('xlim', [-5, 5]);
    ok.push(t.state.points.x[0] === x0 && t.toSpec().xlim[0] === -5);
    // erase removes every group's points within the radius (r = 0.08 * 10)
    var before = t.state.points.x.length, gone = t._erase(5, 5);
    ok.push(gone === 10 && t.state.points.x.length === before - 10);
    // brush keys clamp and sync; clear keeps groups, undoable
    for (i = 0; i < 60; i++) t.action('brush-up');
    ok.push(t.ui.brush === 0.5 && synced.brush.value === 0.5);
    t.clear();
    ok.push(t.state.points.x.length === 0 && t.state.groups.length === 3);
    t.undo();
    ok.push(t.state.points.x.length > 0);
    return ok.join(',');
  })()
")

# Scatter + echo guard: two quick undos push G1 then G0 to the sidebar; the
# late echoes (as R forwards them: trimmed vectors) must not commit anything.
run_check("Scatter echoes", engine("scatter"), "
  (function () {
    var t = new DCR.tools.scatter({clientWidth: 0, clientHeight: 0},
                                  {groups: ['A', 'B', 'C']});
    t._flash = function () {};
    var widgets = {}, echoes = [], ok = [];
    var c0 = t.controls();
    Object.keys(c0).forEach(function (k) { widgets[k] = JSON.stringify(c0[k].value); });
    // stand-in for shiny-binding.js pushControls()
    t.onControls(function (msgs) {
      Object.keys(msgs).forEach(function (k) {
        var v = msgs[k].value;
        if (JSON.stringify(v) === widgets[k]) return;
        widgets[k] = JSON.stringify(v);
        t.markPushed(k, v);
        echoes.push([k, k === 'groups' ? v.split(',').map(function (s) { return s.trim(); }) : v]);
      });
    });
    t.receiveControl('groups', ['A', 'B']);          // G1 (user)
    t.receiveControl('groups', ['A']);               // G2 (user, R unboxes)
    echoes = [];                                     // user values: no echo
    t.undo(); t.undo();                              // pushes G1, then G0
    var depth = t.history._index;
    ok.push(echoes.length === 2 && depth === 0);
    echoes.forEach(function (e) { t.receiveControl(e[0], e[1]); });
    ok.push(t.history._index === depth && t.history.canRedo &&
            t.state.groups.join() === 'A,B,C');
    t.redo();
    ok.push(t.state.groups.join() === 'A,B');
    // a real change after the echoes is applied
    t.receiveControl('groups', 'A, Z');
    ok.push(t.state.groups.join() === 'A,Z');
    // scalar from R (auto_unbox) for a pushed one-group list is an echo too
    t.markPushed('groups', 'Q');
    var n = t.history.length;
    t.receiveControl('groups', 'Q');
    ok.push(t.history.length === n);
    return ok.join(',');
  })()
")

# Boxplot: qnorm / qtwopiece match R (values from R 4.5), state logic, drags.
run_check("Boxplot", engine("boxplot"), "
  (function () {
    var B = DCR.tools.boxplot, ok = [];
    // qnorm (Acklam) vs R qnorm()
    var qn = [[0.001, -3.090232306167813], [0.01, -2.326347874040841],
              [0.3, -0.524400512708041], [0.5, 0], [0.9, 1.281551565544601],
              [0.999, 3.090232306167813]];
    ok.push(qn.every(function (a) { return Math.abs(B.qnorm(a[0]) - a[1]) < 1.2e-8; }));
    // qtwopiece vs R: q = (1, 2, 6), p = .01 .25 .5 .75 .99
    var ps = [0.01, 0.25, 0.5, 0.75, 0.99];
    var rn = [-1.44904851906874, 1, 2, 6, 15.79619407627496];
    var ru = [0.04, 1, 2, 6, 9.84];
    ok.push(ps.every(function (p, i) {
      return Math.abs(B.qtwopiece(p, 1, 2, 6, 'normal') - rn[i]) < 1e-6 &&
             Math.abs(B.qtwopiece(p, 1, 2, 6, 'uniform') - ru[i]) < 1e-9;
    }));
    // initial state: 25/50/75 % of ylim, options as scalars or arrays
    var el = {clientWidth: 0, clientHeight: 0};
    var t = new B(el, {variables: ' A ', ylim: [0, 100], n: 50});
    var s = t.toSpec();
    ok.push(s.tool === 'boxplot' && s.variables.join() === 'A' && s.n === 50 &&
            s.q1[0] === 25 && s.q2[0] === 50 && s.q3[0] === 75 && s.family === 'normal');
    t = new B(el, {variables: ['A', 'B', 'C'], ylim: [0, 100]});
    var synced = null;
    t.onControls(function (c) { synced = c; });
    // drag simulation: handles keep q1 < q2 < q3 with a gap of 1 % of ylim
    var rect = {left: 0, top: 0};
    t.el = {clientWidth: 0, clientHeight: 0, getBoundingClientRect: function () { return rect; }};
    t._geo = {left: 0, top: 0, width: 100, height: 100};   // 1 px = 1 data unit
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    // _pointerDown reads the hit from the DOM; drive the stroke directly
    t.beginStroke();
    t._stroke = {id: 1, i: 1, part: 'q2', y0: 50, start: [25, 50, 75]};
    t._pointerMove({pointerId: 1, clientY: 100 - 90});    // q2 -> capped at q3 - 1
    ok.push(t.state.q2[1] === 74);
    t._pointerMove({pointerId: 1, clientY: 100 - 10});    // q2 -> q1 + 1
    ok.push(t.state.q2[1] === 26);
    t._stroke.part = 'q1'; t._pointerMove({pointerId: 1, clientY: 100 - 60});
    ok.push(t.state.q1[1] === 49);   // capped at (start) q2 - 1
    t._stroke.part = 'q1'; t._pointerMove({pointerId: 1, clientY: 100 - 5});
    ok.push(t.state.q1[1] === 5);
    t._stroke.part = 'q3'; t._pointerMove({pointerId: 1, clientY: 100 - 120});
    ok.push(t.state.q3[1] === 100);
    // body: all three move by the same delta, clamped to ylim
    t._stroke = {id: 1, i: 0, part: 'body', y0: 50, start: [25, 50, 75]};
    t._pointerMove({pointerId: 1, clientY: 100 - 60});
    ok.push(t.state.q1[0] === 35 && t.state.q2[0] === 60 && t.state.q3[0] === 85);
    t._pointerMove({pointerId: 1, clientY: 100 - 99});
    ok.push(t.state.q3[0] === 100 && t.state.q1[0] === 50);
    // release: one history entry, ylim expands to show the whiskers
    var depth = t.history._index, ylim0 = t.state.ylim.slice();
    t._pointerUp({pointerId: 1});
    var w = [B.qtwopiece(0.99, t.state.q1[0], t.state.q2[0], t.state.q3[0], 'normal')];
    ok.push(t.history._index === depth + 1 && t.state.ylim[1] > w[0] &&
            t.state.ylim[1] > ylim0[1] && t.state.ylim[0] < 0);
    t.endStroke();
    t.undo();
    ok.push(t.state.ylim[1] === 100 && t.state.q3[0] === 75);
    t.redo();
    t.setControl('ylim', [0, 100]);
    // a click without moving adds no history entry
    depth = t.history._index;
    t.beginStroke();
    t._stroke = {id: 1, i: 2, part: 'q2', y0: 50,
                 start: [t.state.q1[2], t.state.q2[2], t.state.q3[2]]};
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.history._index === depth);
    // reset and align
    t.action('reset');
    ok.push(t.state.q1[0] === 25 && t.state.q3[0] === 75);
    t.state.q2[1] = 30; t.state.q1[1] = 20; t.state.q3[1] = 40; t.commit(t.state);
    t.action('align');
    ok.push(t.state.q2.every(function (v) { return v === 50; }) &&
            t.state.q1[1] === 40 && t.state.q3[1] === 60 && t.state.q3[0] === 75);
    // variables: add (reset quartiles), keep by name, rename, remove
    t.setControl('ylim', [0, 100]);
    t.action('reset');
    t.state.q2[1] = 30; t.state.q1[1] = 20; t.state.q3[1] = 40; t.commit(t.state);
    t.setControl('variables', ['A', 'B', 'C', 'D']);
    ok.push(t.state.q2[1] === 30 && t.state.q2[3] === 50 && t.state.q1[3] === 25);
    t.setControl('variables', ['A', 'X', 'C', 'D']);                // rename B
    ok.push(t.state.q2[1] === 30 && t.toSpec().variables[1] === 'X');
    t.setControl('variables', ['A', 'C', 'D']);                     // remove X
    ok.push(t.state.q2.length === 3 && t.state.q2[0] === 50 && synced.variables.value === 'A, C, D' &&
            synced.active.choices.length === 3);
    // select-k, controls, invalid and unchanged values
    t.action('select-2');
    ok.push(synced.active.value === '2');
    depth = t.history._index;
    t.setControl('n', 0); t.setControl('n', 2e6); t.setControl('n', 1.5);
    t.setControl('family', 'cauchy'); t.setControl('ylim', [5, 5]);
    t.setControl('variables', ['A', 'A']); t.setControl('variables', ['A', 'C', 'D']);
    t.setControl('n', 100); t.setControl('family', 'normal');
    ok.push(t.history._index === depth);
    t.setControl('family', 'uniform'); t.setControl('n', 1e5); t.setControl('ylim', [-5, 5]);
    ok.push(t.history._index === depth + 3 && t.toSpec().family === 'uniform' &&
            t.toSpec().n === 1e5 && t.toSpec().ylim[0] === -5);
    return ok.join(',');
  })()
")

# Boxplot: quartiles stay strictly ordered when the range is widened or offset.
bx_script <- "
  function mk(vars, ylim, family) {
    var t = new DCR.tools.boxplot({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }},
      {variables: vars, ylim: ylim, family: family || 'normal', n: 100000});
    t._geo = {left: 0, top: 0, width: 100, height: 100};
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    return t;
  }
  function strict(t) {
    var s = t.state;
    return s.q1.every(function (v, i) { return v < s.q2[i] && s.q2[i] < s.q3[i]; });
  }
  function drag(t, part, ys) {
    var s = t.state;
    t.beginStroke();
    t._stroke = {id: 1, i: 0, part: part, y0: 50, start: [s.q1[0], s.q2[0], s.q3[0]]};
    var ok = true;
    ys.forEach(function (y) {
      t._pointerMove({pointerId: 1, clientY: 100 - y});
      ok = ok && strict(t);
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
    return ok && strict(t);
  }
"
run_check("Boxplot ordering", engine("boxplot"), paste0(bx_script, "
  (function () {
    var ok = [], parts = ['q1', 'q2', 'q3', 'body'], ys = [-500, 0, 4.95, 5, 5.05, 50, 5000];
    // tight box, then a much wider range: every handle and the body
    parts.forEach(function (part) {
      var t = mk(['A'], [0, 10]);
      t.state.q1[0] = 4.9; t.state.q2[0] = 5; t.state.q3[0] = 5.1; t.commit(t.state);
      t.setControl('ylim', [0, 1000]);
      ok.push(drag(t, part, ys));
    });
    // box much wider than a narrowed range
    parts.forEach(function (part) {
      var t = mk(['A'], [0, 100]);
      t.setControl('ylim', [40, 60]);
      ok.push(drag(t, part, ys));
    });
    // offset range: reset / align / drag keep a strict order
    var t = mk(['A', 'B'], [1e6, 1e6 + 10]);
    var s = t.toSpec();
    ok.push(s.q1[0] < s.q2[0] && s.q2[0] < s.q3[0] && s.q2[0] === 1000005);
    parts.forEach(function (part) { ok.push(drag(t, part, [1e6 + 3, 1e6 + 5, 1e6 + 5.01])); });
    t.action('align'); ok.push(strict(t));
    t.action('reset'); ok.push(strict(t));
    var sp = t.toSpec();
    ok.push(sp.q1.every(function (v, i) { return v < sp.q2[i] && sp.q2[i] < sp.q3[i]; }));
    return ok.join(',');
  })()
"))

# Boxplot: toSpec() JSON from V8 is accepted by R's as_dcr_spec().
suppressMessages(pkgload::load_all(".", quiet = TRUE))
bx_json <- function(setup) {
  cx <- engine("boxplot")
  cx$eval(paste0(bx_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify(T.toSpec())")
}
bx_cases <- list(
  uniform = "var t = mk(['A'], [0, 100], 'uniform');
    t.state.q1[0] = 10; t.state.q2[0] = 15; t.state.q3[0] = 90; t.commit(t.state); return t;",
  asymmetric_normal = "var t = mk(['A', 'B b'], [-3, 7]);
    t.state.q1[0] = 0; t.state.q2[0] = 0.1; t.state.q3[0] = 6; t.commit(t.state); return t;",
  offset = "return mk(['A', 'B', 'C'], [1e6, 1e6 + 10]);",
  widened = "var t = mk(['A'], [0, 10]);
    t.state.q1[0] = 4.9; t.state.q2[0] = 5; t.state.q3[0] = 5.1; t.commit(t.state);
    t.setControl('ylim', [0, 1000]); return t;"
)
for (nm in names(bx_cases)) {
  spec <- tryCatch(as_dcr_spec(jsonlite::fromJSON(bx_json(bx_cases[[nm]]))),
                   error = function(e) {
                     message("Boxplot round trip failed (", nm, "): ", conditionMessage(e))
                     quit(status = 1)
                   })
  stopifnot(inherits(spec, "dcr_spec"), spec$n == 1e5)
}

# Histogram: painting, rebinning, variables, and toSpec() accepted by R.
hg_script <- "
  function mk(vars, xlim, nbins) {
    var t = new DCR.tools.histogram({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }},
      {variables: vars, xlim: xlim, nbins: nbins, n: 1000});
    t._geo = {left: 0, top: 0, width: 100, height: 100};   // 1 px = 1 percent
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    return t;
  }
  function stroke(t, pts) {      // pts: [[x, y], ...] in px
    t._pointerDown({button: 0, pointerId: 1, clientX: pts[0][0], clientY: pts[0][1]});
    pts.slice(1).forEach(function (p) {
      t._pointerMove({pointerId: 1, clientX: p[0], clientY: p[1]});
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
  }
  function near(a, b) { return Math.abs(a - b) < 1e-9; }
"
run_check("Histogram", engine("histogram"), paste0(hg_script, "
  (function () {
    var H = DCR.tools.histogram, ok = [];
    var t = mk([' A ', 'B'], [0, 10], 10);
    var s = t.toSpec();
    ok.push(s.tool === 'histogram' && s.variables.join() === 'A,B' && s.nbins === 10 &&
            s.n === 1000 && s.weights.length === 2 && s.weights[0].length === 10 &&
            s.weights.every(function (r) { return r.every(function (v) { return v === 0; }); }));
    // one stroke = one history entry; only the active variable changes
    var depth = t.history._index;
    stroke(t, [[5, 80], [15, 60], [25, 40]]);
    ok.push(t.history._index === depth + 1 && t.state.weights[1].every(function (v) { return v === 0; }));
    ok.push(near(t.state.weights[0][0], 0.2) && near(t.state.weights[0][1], 0.4) &&
            near(t.state.weights[0][2], 0.6));
    // fast drag skipping bins: interpolated, no gaps
    t = mk(['A'], [0, 10], 10);
    stroke(t, [[5, 100], [95, 0]]);
    var w = t.state.weights[0];
    ok.push(w.every(function (v, i) { return near(v, i / 9); }));
    // drag past the plot edge clamps; height clamped to 0..1
    t = mk(['A'], [0, 10], 10);
    stroke(t, [[50, 50], [500, -300]]);
    ok.push(t.state.weights[0][9] === 1 && t.state.weights[0][5] > 0);
    // a press outside the plot is ignored
    var d2 = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: -5, clientY: 50});
    ok.push(!t._stroke && t.history._index === d2);
    // undo restores the whole stroke; a control mid-stroke is queued
    t.undo(); ok.push(t.state.weights[0].every(function (v) { return v === 0; }));
    t._pointerDown({button: 0, pointerId: 1, clientX: 5, clientY: 50});
    t.receiveControl('n', 77);
    ok.push(t.state.n === 1000);
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.state.n === 77);
    // actions
    t = mk(['A', 'B'], [0, 10], 4);
    t.action('select-2'); t.action('flat');
    ok.push(t.state.weights[1].join() === '0.5,0.5,0.5,0.5' && t.state.weights[0].join() === '0,0,0,0');
    var n0 = t.history.length; t.action('flat'); ok.push(t.history.length === n0);
    t.action('reset'); ok.push(t.state.weights[1].join() === '0,0,0,0');
    ok.push(t.history.length === n0 + 1);
    // set controls: unchanged or invalid values add no history
    t = mk(['A'], [0, 10], 10);
    var d = t.history._index;
    t.setControl('nbins', 10); t.setControl('xlim', [0, 10]); t.setControl('n', 1000);
    t.setControl('nbins', 0); t.setControl('nbins', 101); t.setControl('nbins', 2.5);
    t.setControl('xlim', [5, 5]);
    ok.push(t.history._index === d);
    // rebin: max unchanged, one history entry
    t.state.weights[0] = [0, 0.5, 1, 0.5, 0, 0, 0, 0, 0, 0]; t.commit(t.state);
    d = t.history._index;
    t.setControl('nbins', 5);
    w = t.state.weights[0];
    ok.push(t.history._index === d + 1 && w.length === 5 && near(Math.max.apply(null, w), 1) &&
            near(w[0] / w[1], (0.5 / 2) / (1.5 / 2)));
    t.setControl('nbins', 20);
    ok.push(t.state.weights[0].length === 20 && near(Math.max.apply(null, t.state.weights[0]), 1));
    // splitting bins keeps heights exactly
    t = mk(['A'], [0, 10], 4);
    t.state.weights[0] = [0.2, 1, 0.6, 0.4]; t.commit(t.state);
    t.setControl('nbins', 8);
    ok.push(t.state.weights[0].every(function (v, i) {
      return near(v, [0.2, 0.2, 1, 1, 0.6, 0.6, 0.4, 0.4][i]);
    }));
    // xlim: bins outside the old range get 0, inside keep their shape
    t = mk(['A'], [0, 10], 10);
    t.state.weights[0] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]; t.commit(t.state);
    t.setControl('xlim', [-10, 10]);
    w = t.state.weights[0];
    ok.push(w.slice(0, 5).every(function (v) { return v === 0; }) &&
            w.slice(5).every(function (v) { return near(v, 1); }));
    t.undo();
    ok.push(t.state.xlim.join() === '0,10' && t.state.weights[0].every(function (v) { return v === 1; }));
    // variables: keep by name, rename pairs in order, new starts at zero
    t = mk(['A', 'B', 'C'], [0, 10], 3);
    t.state.weights = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]; t.commit(t.state);
    t.setControl('variables', 'C, A, D');
    ok.push(JSON.stringify(t.state.weights) === '[[0,0,1],[1,0,0],[0,1,0]]');   // B renamed to D
    t.setControl('variables', 'C, X, D, E');
    ok.push(JSON.stringify(t.state.weights) === '[[0,0,1],[0,0,0],[0,1,0],[0,0,0]]' &&
            t.state.variables.join() === 'C,X,D,E');
    t.setControl('variables', 'D'); ok.push(JSON.stringify(t.state.weights) === '[[0,1,0]]');
    t.setControl('variables', 'D, D'); ok.push(t.state.variables.join() === 'D');
    // scalar options from R (auto_unbox)
    t = new H({clientWidth: 0, clientHeight: 0}, {variables: 'Q', xlim: [1, 2], nbins: 3, n: 5});
    ok.push(t.toSpec().variables.join() === 'Q' && t.toSpec().nbins === 3);
    return ok.join(',');
  })()
"))

# Histogram: toSpec() JSON from V8 is accepted by R's as_dcr_spec().
hg_json <- function(setup) {
  cx <- engine("histogram")
  cx$eval(paste0(hg_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify(T.toSpec())")
}
hg_cases <- list(
  one_variable = "var t = mk(['A'], [0, 10], 10); stroke(t, [[5, 80], [55, 20]]); return t;",
  one_bin = "var t = mk(['A', 'B'], [0, 10], 1); stroke(t, [[50, 50]]); return t;",
  offset_xlim = "var t = mk(['A'], [1000, 1010], 10); t.action('flat'); return t;",
  after_rebin = "var t = mk(['A', 'B'], [0, 10], 10); t.action('flat');
    t.setControl('nbins', 7); t.setControl('xlim', [-3, 4]); t.setControl('nbins', 100); return t;",
  all_zero_second = "var t = mk(['A', 'B'], [0, 10], 10); t.action('flat'); return t;",
  fresh_variables = "var t = mk(['A'], [0, 10], 5); t.action('flat');
    t.setControl('variables', 'A, B'); return t;"
)
for (nm in names(hg_cases)) {
  spec <- tryCatch(as_dcr_spec(jsonlite::fromJSON(hg_json(hg_cases[[nm]]))),
                   error = function(e) {
                     message("Histogram round trip failed (", nm, "): ", conditionMessage(e))
                     quit(status = 1)
                   })
  stopifnot(inherits(spec, "dcr_spec"), spec$n == 1000,
            is.matrix(spec$weights), all(spec$weights >= 0))
  if (nm %in% c("all_zero_second", "fresh_variables")) {
    df <- sample_spec(spec, 50)
    stopifnot(identical(attr(df, "dropped"), "B"), ncol(df) == 1L)
  }
}


# Count: painting, interpolation, levels, ymax, actions, toSpec() accepted by R.
ct_script <- "
  function mk(vars, cats, ymax) {
    var t = new DCR.tools.count({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }},
      {variables: vars, categories: cats, ymax: ymax});
    t._geo = {left: 0, top: 0, width: 100, height: 100};   // 1 px = 1 percent
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    return t;
  }
  function cx(t, c, v) {         // x of the centre of bar (category c, variable v)
    var G = t._slot();
    return c * G.w + G.pad + (v + 0.5) * G.bw;
  }
  function py(t, v) { return 100 - v * 100 / t.state.ymax; }   // y px of count v
  function stroke(t, pts) {      // pts: [[x, y], ...] in px
    t._pointerDown({button: 0, pointerId: 1, clientX: pts[0][0], clientY: pts[0][1]});
    pts.slice(1).forEach(function (p) {
      t._pointerMove({pointerId: 1, clientX: p[0], clientY: p[1]});
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
  }
  function allInt(t) {
    return t.state.counts.every(function (r) {
      return r.every(function (v) { return v === Math.round(v) && v >= 0; });
    });
  }
"
run_check("Count", engine("count"), paste0(ct_script, "
  (function () {
    var ok = [], t = mk([' A ', 'B'], ['x', 'y', 'z'], 20), s = t.toSpec();
    ok.push(s.tool === 'count' && s.variables.join() === 'A,B' && s.categories.join() === 'x,y,z' &&
            JSON.stringify(s.counts) === '[[5,5,5],[5,5,5]]');
    ok.push(mk(['A'], ['x'], 3).state.counts[0][0] === 3);       // initial min(5, ymax)
    // only the bar under the pointer changes; integer snapping; one history entry
    var depth = t.history._index;
    stroke(t, [[cx(t, 1, 1), py(t, 12.4)]]);
    ok.push(JSON.stringify(t.state.counts) === '[[5,5,5],[5,12,5]]' && t.history._index === depth + 1);
    stroke(t, [[cx(t, 0, 0), py(t, 12.6)], [cx(t, 2, 0), py(t, 3.2)]]);
    ok.push(t.state.counts[0][0] === 13 && t.state.counts[0][2] === 3 && allInt(t));
    // skipped bars are interpolated on a fast drag: 6 bars, 0 -> 20
    t = mk(['A', 'B'], ['x', 'y', 'z'], 20);
    stroke(t, [[cx(t, 0, 0), 100], [cx(t, 2, 1), 0]]);
    ok.push(JSON.stringify(t.state.counts) === '[[0,8,16],[4,12,20]]');
    // drag past the plot edge clamps bar and height
    t = mk(['A'], ['x', 'y'], 10);
    stroke(t, [[cx(t, 0, 0), 50], [500, -300]]);
    ok.push(t.state.counts[0][1] === 10 && t.state.counts[0][0] <= 10);
    // press outside the plot is ignored; undo restores the whole stroke
    var d2 = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: -5, clientY: 50});
    ok.push(!t._stroke && t.history._index === d2);
    t.undo(); ok.push(t.state.counts[0].join() === '5,5');
    // a press that changes nothing adds no history; a control mid-stroke is queued
    d2 = t.history._index;
    stroke(t, [[cx(t, 0, 0), py(t, 5)]]);
    ok.push(t.history._index === d2);
    t._pointerDown({button: 0, pointerId: 1, clientX: cx(t, 0, 0), clientY: 50});
    t.receiveControl('ymax', 40);
    ok.push(t.state.ymax === 10);
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.state.ymax === 40);
    // actions: one entry each, none when unchanged
    t = mk(['A', 'B'], ['x', 'y'], 7);
    t.action('align-top'); ok.push(JSON.stringify(t.state.counts) === '[[7,7],[7,7]]');
    var n0 = t.history.length; t.action('align-top'); ok.push(t.history.length === n0);
    t.action('align-middle'); ok.push(t.state.counts[0].join() === '4,4' && t.history.length === n0 + 1);
    t.action('align-bottom'); ok.push(t.state.counts[1].join() === '0,0' && t.history.length === n0 + 2);
    t.action('select-2'); ok.push(t.ui.active === 1 && t.history.length === n0 + 2);
    // clear zeroes counts, keeps names and ymax
    t.action('align-top'); t.clear();
    ok.push(t.state.counts[0].join() === '0,0' && t.state.ymax === 7 && t.state.variables.join() === 'A,B');
    // ymax: unchanged/invalid add no history; below a count it is raised, never truncating
    t = mk(['A', 'B'], ['x', 'y'], 20);
    t.state.counts = [[3, 12], [0, 9]]; t.commit(t.state);
    var d = t.history._index, flashed = [];
    t._flash = function (m) { flashed.push(m); };
    t.setControl('ymax', 20); t.setControl('ymax', 0); t.setControl('ymax', 2.5);
    ok.push(t.history._index === d && !flashed.length);
    t.setControl('ymax', 5);
    ok.push(t.state.ymax === 12 && JSON.stringify(t.state.counts) === '[[3,12],[0,9]]' &&
            flashed.length === 1 && flashed[0] === 'Y max raised to 12 to keep your counts');
    t.setControl('ymax', 5);       // already 12: counts kept, notice again, no history
    ok.push(t.state.ymax === 12 && flashed.length === 2);
    t.setControl('ymax', 30); ok.push(t.state.ymax === 30);
    // variables / categories: keep by name, rename pairs in order, new starts at zero
    t = mk(['A', 'B', 'C'], ['x', 'y'], 20);
    t.state.counts = [[1, 2], [3, 4], [5, 6]]; t.commit(t.state);
    t.setControl('variables', 'C, A, D');
    ok.push(JSON.stringify(t.state.counts) === '[[5,6],[1,2],[3,4]]');   // B renamed to D
    t.setControl('variables', 'C, X, D, E');
    ok.push(JSON.stringify(t.state.counts) === '[[5,6],[0,0],[3,4],[0,0]]');
    t.setControl('variables', 'D'); ok.push(JSON.stringify(t.state.counts) === '[[3,4]]');
    t.setControl('categories', 'y, x, w');
    ok.push(JSON.stringify(t.state.counts) === '[[4,3,0]]' && t.state.categories.join() === 'y,x,w');
    t.setControl('categories', 'y, q, w');   // x renamed to q
    ok.push(JSON.stringify(t.state.counts) === '[[4,3,0]]');
    t.setControl('categories', 'q');
    ok.push(JSON.stringify(t.state.counts) === '[[3]]');
    var dd = t.history._index;
    t.setControl('variables', 'D, D'); t.setControl('categories', ' , x'); t.setControl('variables', 'D');
    ok.push(t.history._index === dd && t.state.variables.join() === 'D');
    t.undo(); ok.push(JSON.stringify(t.state.counts) === '[[4,3,0]]');
    // total cap: align-top at ymax 1e6 on 10 x 10 bars, and painting, stay <= 1e6
    function tot(t) { return t.state.counts.reduce(function (a, r) { return a + r.reduce(function (b, v) { return b + v; }, 0); }, 0); }
    var big = 'A,B,C,D,E,F,G,H,I,J'.split(','), bigc = 'a,b,c,d,e,f,g,h,i,j'.split(',');
    t = mk(big, bigc, 1e6);
    t.action('align-top');
    ok.push(tot(t) === 1e6 && t.state.counts[0][0] === 1e4 && t.history.length >= 2);
    t.action('align-middle'); ok.push(tot(t) === 1e6 && t.state.counts[3][3] === 1e4);
    t = mk(big, bigc, 1e6); t.action('align-bottom');
    stroke(t, [[cx(t, 0, 0), 0], [cx(t, 9, 9), 0]]);
    ok.push(tot(t) <= 1e6 && tot(t) === 1e6);
    // scalar options from R (auto_unbox)
    t = new DCR.tools.count({clientWidth: 0, clientHeight: 0},
                            {variables: 'Q', categories: 'k', ymax: 4});
    ok.push(t.toSpec().variables.join() === 'Q' && t.toSpec().counts[0].join() === '4');
    return ok.join(',');
  })()
"))

# Count: toSpec() JSON from V8 is accepted by R's as_dcr_spec().
ct_json <- function(setup) {
  cx <- engine("count")
  cx$eval(paste0(ct_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify(T.toSpec())")
}
ct_cases <- list(
  one_by_one = "var t = mk(['A'], ['x'], 10); stroke(t, [[50, 70]]); return t;",
  one_by_three = "var t = mk(['A'], ['x', 'y', 'z'], 10); stroke(t, [[10, 100], [90, 0]]); return t;",
  three_by_one = "var t = mk(['A', 'B', 'C'], ['x'], 10); stroke(t, [[10, 100], [90, 0]]); return t;",
  after_rename_remove = "var t = mk(['A', 'B', 'C'], ['x', 'y'], 10);
    t.setControl('variables', 'A, Z'); t.setControl('categories', 'x, q'); return t;",
  after_ymax = "var t = mk(['A'], ['x', 'y'], 10); t.action('align-top');
    t.setControl('ymax', 3); t.setControl('ymax', 50); return t;",
  all_zeros = "var t = mk(['A', 'B'], ['x', 'y'], 10); t.action('align-bottom'); return t;",
  capped_total = "var v = 'A,B,C,D,E,F,G,H,I,J'.split(','); var t = mk(v, v, 1e6);
    t.action('align-top'); return t;"
)
for (nm in names(ct_cases)) {
  spec <- tryCatch(as_dcr_spec(jsonlite::fromJSON(ct_json(ct_cases[[nm]]))),
                   error = function(e) {
                     message("Count round trip failed (", nm, "): ", conditionMessage(e))
                     quit(status = 1)
                   })
  stopifnot(inherits(spec, "dcr_spec"), is.matrix(spec$counts),
            identical(spec_is_empty(spec), nm == "all_zeros"))
  if (nm == "capped_total") stopifnot(sum(spec$counts) <= 1e6) else
  if (nm != "all_zeros") stopifnot(nrow(sample_spec(spec, NULL)) == sum(spec$counts))
}

# Scatter on an offset range: coordinates are rounded relative to the range,
# so points 0.001 apart near 1e5 stay distinct, in toSpec() and through R.
sc_offset <- "
  var t = new DCR.tools.scatter({clientWidth: 0, clientHeight: 0},
                                {xlim: [1e5, 1e5 + 10], ylim: [-1e5 - 10, -1e5]});
  for (var i = 0; i < 50; i++) {
    t.state.points.x.push(1e5 + 5 + i * 0.001);
    t.state.points.y.push(-1e5 - 5 - i * 0.001);
    t.state.points.g.push(i % 3);
  }
  t.commit(t.state);
"
run_check("Scatter offset range", engine("scatter"), paste0(sc_offset, "
  (function () {
    var s = t.toSpec(), ok = [];
    var ux = s.points.x.filter(function (v, i, a) { return a.indexOf(v) === i; });
    var uy = s.points.y.filter(function (v, i, a) { return a.indexOf(v) === i; });
    ok.push(ux.length === 50 && uy.length === 50);
    ok.push(Math.abs(s.points.x[1] - s.points.x[0] - 0.001) < 1e-9);
    // drawn on 0..10, then zoomed out to 0..1e6: the points' own spread rules
    var z = new DCR.tools.scatter({clientWidth: 0, clientHeight: 0}, {});
    z.state.points = {x: [1.234567, 1.234568], y: [2, 3], g: [0, 0]};
    z.commit(z.state);
    z.setControl('xlim', [0, 1e6]);
    ok.push(z.toSpec().points.x[0] !== z.toSpec().points.x[1]);
    return ok.join(',');
  })()
"))
local({
  cx <- engine("scatter")
  cx$eval(sc_offset)
  spec <- as_dcr_spec(jsonlite::fromJSON(cx$eval("JSON.stringify(t.toSpec())")))
  df <- sample_spec(spec, NULL)
  stopifnot(nrow(df) == 50L, length(unique(df$x)) == 50L,
            length(unique(df$y)) == 50L,
            isTRUE(all.equal(sort(df$x), 1e5 + 5 + (0:49) * 0.001)))
})

# Done flushes the sidebar: values still in the fields (not yet committed
# through R) reach toSpec(); invalid ones are ignored and never stop Done.
flush_script <- "
  var sent = [];
  window.Shiny = {setInputValue: function (name, value) { sent.push([name, value]); }};
  var sidebar = {};
  DCR.flushSidebar = function (tool) { tool.flushControls(sidebar); };
  function el() { return {clientWidth: 0, clientHeight: 0}; }
  function doneSpec(tool) {
    sent = [];
    DCR.done(tool);
    return sent.length === 1 && sent[0][0] === 'tool_done:dcr.spec' ? JSON.parse(sent[0][1]) : null;
  }
"
run_check("Done flush", engine(c("scatter", "histogram", "boxplot", "count")),
          paste0(flush_script, "
  (function () {
    var ok = [], s;
    // scatter: raw widget values (text input, fields input objects/arrays)
    var t = new DCR.tools.scatter(el(), {groups: ['A', 'B', 'C']});
    t._flash = function () {};
    t.state.points = {x: [1, 2], y: [1, 2], g: [0, 1]}; t.commit(t.state);
    sidebar = {active: '1', groups: 'A, Q, C', mode: 'spray', brush: 0.08,
               density: 40, xlim: [-5, 5], ylim: [null, 10],
               names: {x: 'h', y: 'w', group: 'sp'}};
    s = doneSpec(t);
    ok.push(s !== null && s.groups.join() === 'A,Q,C' && s.points.group[1] === 'Q' &&
            s.xlim.join() === '-5,5' && s.ylim.join() === '0,10' && s.names.x === 'h');
    // invalid values everywhere: nothing applied, Done still sends
    var depth = t.history._index;
    sidebar = {groups: 'A, A', xlim: ['', 3], names: {x: 'a', y: 'a', group: 'g'},
               brush: 'big', active: '9'};
    s = doneSpec(t);
    ok.push(s !== null && t.history._index === depth && s.groups.join() === 'A,Q,C');
    // a throwing setControl does not stop Done
    var orig = t.setControl;
    t.setControl = function () { throw new Error('boom'); };
    sidebar = {groups: 'X'};
    ok.push(doneSpec(t) !== null);
    t.setControl = orig;
    // no flushSidebar (e.g. not loaded): Done still sends
    var keep = DCR.flushSidebar; DCR.flushSidebar = null;
    ok.push(doneSpec(t) !== null);
    DCR.flushSidebar = function () { throw new Error('dom'); };
    ok.push(doneSpec(t) !== null);
    DCR.flushSidebar = keep;
    // histogram: n / nbins from numericInput (numbers or null), variables text
    var h = new DCR.tools.histogram(el(), {variables: 'V1', n: 100});
    h._flash = function () {};
    sidebar = {active: '1', variables: 'V1, V2', n: 250, xlim: [0, 20], nbins: null};
    s = doneSpec(h);
    ok.push(s.n === 250 && s.variables.join() === 'V1,V2' && s.xlim[1] === 20 && s.nbins === 10);
    // boxplot
    var b = new DCR.tools.boxplot(el(), {variables: ['V1', 'V2', 'V3']});
    sidebar = {active: '1', variables: 'V1, V2', n: 42, family: 'uniform', ylim: [0, 100]};
    s = doneSpec(b);
    ok.push(s.n === 42 && s.variables.join() === 'V1,V2' && s.family === 'uniform' &&
            s.ylim[1] === 100);
    // count
    var c = new DCR.tools.count(el(), {variables: ['V1', 'V2'], categories: ['C1', 'C2', 'C3']});
    c._flash = function () {};
    sidebar = {variables: 'V1, V2, V3', categories: 'C1, C2', ymax: 30};
    s = doneSpec(c);
    ok.push(s.variables.join() === 'V1,V2,V3' && s.categories.join() === 'C1,C2' &&
            s.counts.length === 3 && c.state.ymax === 30);
    return ok.join(',');
  })()
"))

# Histogram / count: removing a level with data says so on the canvas
# (undoable); histogram clear adds no history entry when already empty.
run_check("Removal notices", engine(c("histogram", "count")), paste0(hg_script, "
  function mkc(vars, cats) {
    return new DCR.tools.count({clientWidth: 0, clientHeight: 0},
                               {variables: vars, categories: cats, ymax: 20});
  }
  (function () {
    var ok = [], msgs = [];
    var t = mk(['A', 'B', 'C'], [0, 10], 10);
    t._flash = function (m) { msgs.push(m); };
    var depth = t.history._index;
    t.clear();
    ok.push(t.history._index === depth);
    t.ui.active = 1; t.action('flat');
    t.setControl('variables', 'A, B');            // C had no bars: no notice
    ok.push(msgs.length === 0);
    t.setControl('variables', 'A');               // B had bars
    ok.push(msgs.length === 1 && msgs[0].indexOf('B removed') === 0 &&
            msgs[0].indexOf('Ctrl+Z to undo') > 0);
    t.undo();
    ok.push(t.state.variables.join() === 'A,B' && t.state.weights[1][0] === 0.5);
    t.clear(); depth = t.history._index; t.clear();
    ok.push(t.history._index === depth);
    var c = mkc(['A', 'B', 'C'], ['x', 'y', 'z']), cm = [];
    c._flash = function (m) { cm.push(m); };
    c.setControl('variables', 'A, C');            // B: 3 x 5 = 15 observations
    ok.push(cm.length === 1 && cm[0].indexOf('15 observations of B removed') === 0);
    c.setControl('categories', 'x, y');           // z: 2 x 5 = 10
    ok.push(cm.length === 2 && cm[1].indexOf('10 observations of z removed') === 0);
    c.setControl('categories', 'x, q');           // rename: no notice
    ok.push(cm.length === 2);
    c.action('align-bottom');
    c.setControl('variables', 'A');               // all zero: no notice
    ok.push(cm.length === 2);
    c.undo(); c.undo(); c.undo(); c.undo();
    ok.push(c.state.variables.join() === 'A,C' && c.state.categories.join() === 'x,y,z');
    return ok.join(',');
  })()
"))

# Density: pull / paint maths, strokes, brush clamp, xlim resampling,
# variables, actions, and toSpec() accepted by R.
dn_script <- "
  function mk(vars, xlim, o) {
    var opts = {variables: vars, xlim: xlim, n: 1000};
    for (var k in (o || {})) opts[k] = o[k];
    var t = new DCR.tools.density({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }}, opts);
    t._geo = {left: 0, top: 0, width: 100, height: 100};   // 1 px = 1 percent
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    return t;
  }
  function stroke(t, pts) {      // pts: [[x, y], ...] in px; paint frames are 100 ms apart
    t._pointerDown({button: 0, pointerId: 1, clientX: pts[0][0], clientY: pts[0][1]});
    pts.slice(1).forEach(function (p) {
      if (t._stroke) t._stroke.last -= 100;
      t._pointerMove({pointerId: 1, clientX: p[0], clientY: p[1]});
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
  }
  function near(a, b, e) { return Math.abs(a - b) < (e || 1e-9); }
  function finite01(t) {
    return t.state.curves.every(function (c) {
      return c.length === 201 && c[0] === 0 && c[200] === 0 &&
        c.every(function (v) { return isFinite(v) && v >= 0 && v <= 1; });
    });
  }
  function zero(c) { return c.every(function (v) { return v === 0; }); }
"
run_check("Density", engine("density"), paste0(dn_script, "
  (function () {
    var D = DCR.tools.density, ok = [], i;
    var xs = D.grid([0, 10]);
    // initial state: one Bell per variable, ends 0, names trimmed, scalar options
    var t = mk([' A ', 'B'], [0, 10]);
    var s = t.toSpec();
    ok.push(s.tool === 'density' && s.variables.join() === 'A,B' && s.n === 1000 &&
            s.curves.length === 2 && s.curves[0].length === 201 && finite01(t) &&
            near(s.curves[0][100], 0.85) && s.curves[0][0] === 0);
    var q = new D({clientWidth: 0, clientHeight: 0}, {variables: 'Q', xlim: [1, 2], n: 5});
    ok.push(q.toSpec().variables.join() === 'Q' && q.toSpec().xlim.join() === '1,2');
    // presets: Flat 0.5 inside, ends 0; Skewed peaks near 0.855 and stays in 0..1
    var flat = D.shape('flat', [0, 10]), sk = D.shape('skew', [0, 10]);
    ok.push(flat[0] === 0 && flat[200] === 0 && flat[1] === 0.5 && flat[199] === 0.5);
    ok.push(near(Math.max.apply(null, sk), 0.855, 0.01) && sk.every(function (v) { return v >= 0 && v <= 1; }));
    // pull: centre moves by dy, 3 sigma away < 2 % of dy, ends stay 0
    var snap = D.shape('bell', [0, 10]), sig = 1.2;
    var p = D.pull(snap, xs, 5, 0.1, sig);
    ok.push(near(p[100] - snap[100], 0.1) && Math.abs(p[172] - snap[172]) < 0.1 * 0.02 &&
            p[0] === 0 && p[200] === 0);
    var up = D.pull(snap, xs, 5, 5, sig), dn = D.pull(snap, xs, 5, -5, sig);
    ok.push(up[100] === 1 && dn[100] === 0 && up[0] === 0 && up[200] === 0 &&
            up.every(function (v) { return v >= 0 && v <= 1; }) && snap[100] === 0.85);
    ok.push(D.pull(snap, xs, 5, 0, sig).join() === snap.join());
    // paint: converges to the cursor height near x0, far points unchanged
    var ys = D.shape('flat', [0, 10]), far0 = ys[10];
    for (i = 0; i < 60; i++) D.paint(ys, xs, {x: 5, y: 0.9}, 1, 16);
    ok.push(near(ys[100], 0.9, 1e-3) && near(ys[10], far0, 1e-3) && ys[0] === 0 && ys[200] === 0);
    var y2 = D.shape('flat', [0, 10]);
    D.paint(y2, xs, {x: 5, y: 0}, 1, 1000);        // dt capped: factor 1
    ok.push(y2[100] === 0 && near(y2[1], 0.5, 1e-4));
    var y3 = D.shape('flat', [0, 10]); D.paint(y3, xs, {x: 5, y: 1}, 1, 0);
    ok.push(y3.join() === D.shape('flat', [0, 10]).join());
    // a Pull drag: one history entry, only the active variable, undo restores
    t = mk(['A', 'B'], [0, 10]);
    var depth = t.history._index, before = JSON.stringify(t.state);
    stroke(t, [[50, 35], [50, 25], [50, 15]]);                 // up by 0.2
    ok.push(t.history._index === depth + 1 && finite01(t) &&
            near(t.state.curves[0][100], 1) &&
            t.state.curves[1].join() === D.shape('bell', [0, 10]).join());
    t.undo(); ok.push(JSON.stringify(t.state) === before);
    // a Paint drag
    t.ui.mode = 'paint';
    stroke(t, [[50, 50], [52, 90], [55, 90], [58, 90]]);
    ok.push(t.history._index === depth + 1 && finite01(t) && t.state.curves[0][100] < 0.5);
    t.undo();
    // REVIEW FOCUS 1: 200 press/release cycles without movement never block
    depth = t.history._index; var len = t.history.length;
    for (i = 0; i < 200; i++) {
      t.ui.mode = i % 2 ? 'paint' : 'pull';
      stroke(t, [[20 + i % 60, 30]]);
    }
    ok.push(t.history._index === depth && t.history.length === len && !t._stroke &&
            !t._busy && finite01(t) && JSON.stringify(t.state) === before);
    // ... also with the stroke-ending events firing twice (up, then lostpointercapture)
    t._pointerDown({button: 0, pointerId: 1, clientX: 50, clientY: 50});
    t._pointerUp({pointerId: 1}); t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.history._index === depth && !t._stroke);
    // then one real drag adds exactly one entry; undo restores
    t.ui.mode = 'pull';
    stroke(t, [[50, 50], [50, 30]]);
    ok.push(t.history._index === depth + 1 && t.history.length === depth + 2);
    t.undo(); ok.push(JSON.stringify(t.state) === before);
    // a press outside the plot or with another button starts nothing
    t._pointerDown({button: 0, pointerId: 1, clientX: -5, clientY: 50});
    t._pointerDown({button: 2, pointerId: 1, clientX: 50, clientY: 50});
    ok.push(!t._stroke);
    // a control mid-stroke is queued until the stroke is committed
    t._pointerDown({button: 0, pointerId: 1, clientX: 50, clientY: 50});
    t.receiveControl('n', 77);
    ok.push(t.state.n === 1000);
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.state.n === 77);
    // REVIEW FOCUS 3: extreme brush widths are clamped, weights stay finite
    t = mk(['A'], [0, 10]);
    t.setControl('brush', 1e9);
    ok.push(t.ui.brush === 1 && near(t._sigma(), 10));
    t.setControl('brush', 0);
    ok.push(t.ui.brush === 0.005 && near(t._sigma(), 0.05));
    t.setControl('brush', -3); ok.push(t.ui.brush === 0.005);
    t.setControl('brush', 'big'); t.setControl('brush', null); t.setControl('brush', '');
    ok.push(t.ui.brush === 0.005);
    [1e9, 0].forEach(function (b) {
      t.setControl('brush', b);
      stroke(t, [[50, 50], [50, 20], [60, 20]]);
      ok.push(finite01(t));
      t.ui.mode = 'paint'; stroke(t, [[40, 80], [45, 80], [60, 10]]); t.ui.mode = 'pull';
      ok.push(finite01(t));
    });
    var o2 = mk(['A'], [0, 10], {brush: 50});
    ok.push(o2.ui.brush === 1);
    // brush keys: x1.2 or /1.2 on the slider step, clamped, synced
    t = mk(['A'], [0, 10]); var synced = null;
    t.onControls(function (c) { synced = c; });
    t.action('brush-up');
    ok.push(t.ui.brush === 0.145 && synced.brush.value === 0.145);
    t.action('brush-down'); t.action('brush-down');
    ok.push(t.ui.brush < 0.12 && t.ui.brush > 0.09);
    for (i = 0; i < 80; i++) t.action('brush-up');
    ok.push(t.ui.brush === 1);
    for (i = 0; i < 80; i++) t.action('brush-down');
    ok.push(t.ui.brush === 0.005 && synced.brush.value === 0.005);
    // sigma follows xlim (it is a fraction of the range)
    t = mk(['A'], [0, 10]); t.setControl('xlim', [0, 100]);
    ok.push(near(t._sigma(), 12));
    // REVIEW FOCUS 4: xlim to a disjoint range -> all zero, one entry, undoable
    t = mk(['A', 'B'], [0, 10]); depth = t.history._index;
    t.setControl('xlim', [20, 30]);
    ok.push(t.history._index === depth + 1 && t.state.curves.every(zero) &&
            t.state.xlim.join() === '20,30' && finite01(t));
    t.undo(); ok.push(t.state.xlim.join() === '0,10' && !zero(t.state.curves[0]));
    // xlim overlapping: shape kept at its place on the axis, ends pinned
    t = mk(['A'], [0, 10]); var c0 = t.state.curves[0].slice();
    t.setControl('xlim', [0, 20]);
    var w = t.state.curves[0];
    ok.push(near(w[50], c0[100], 1e-9) && near(w[0], 0) && w[200] === 0 &&
            w.slice(101).every(function (v) { return v === 0; }) && !zero(w));
    t.setControl('xlim', [-10, 20]);
    ok.push(finite01(t) && near(Math.max.apply(null, t.state.curves[0]), 0.85, 0.01));
    var r = D.resample(c0, [0, 10], [0, 10]);
    ok.push(r.every(function (v, j) { return near(v, c0[j], 1e-12); }));
    // invalid or unchanged controls add no history
    t = mk(['A'], [0, 10]); depth = t.history._index;
    t.setControl('xlim', [0, 10]); t.setControl('xlim', [5, 5]); t.setControl('xlim', [10, 0]);
    t.setControl('xlim', ['', 3]); t.setControl('n', 1000); t.setControl('n', 0);
    t.setControl('n', 2e6); t.setControl('n', 1.5);
    t.setControl('variables', 'A'); t.setControl('variables', 'A, A'); t.setControl('variables', ' , x');
    t.setControl('mode', 'spray'); t.setControl('active', '9');
    ok.push(t.history._index === depth);
    t.setControl('mode', 'paint'); ok.push(t.ui.mode === 'paint' && t.history._index === depth);
    t.setControl('n', 5e5); ok.push(t.history._index === depth + 1 && t.toSpec().n === 5e5);
    // actions: bell / flat / skew on the active variable only; no entry when unchanged
    t = mk(['A', 'B'], [0, 10]);
    t.action('select-2'); t.action('flat');
    ok.push(t.state.curves[1].join() === D.shape('flat', [0, 10]).join() &&
            t.state.curves[0].join() === D.shape('bell', [0, 10]).join());
    var n0 = t.history.length; t.action('flat'); ok.push(t.history.length === n0);
    t.action('skew'); ok.push(t.state.curves[1].join() === D.shape('skew', [0, 10]).join() &&
                              t.history.length === n0 + 1);
    t.action('bell'); ok.push(t.state.curves[1].join() === D.shape('bell', [0, 10]).join());
    n0 = t.history.length; t.action('bell'); ok.push(t.history.length === n0);
    // clear: back to Bell for every variable, names / range / n kept, one entry, none if unchanged
    t.action('flat'); t.ui.active = 0; t.action('flat');
    n0 = t.history.length; t.clear();
    ok.push(t.state.curves.every(function (c) { return c.join() === D.shape('bell', [0, 10]).join(); }) &&
            t.state.variables.join() === 'A,B' && t.history.length === n0 + 1);
    t.clear(); ok.push(t.history.length === n0 + 1);
    // variables: keep by name, rename pairs in order, new starts as a Bell
    t = mk(['A', 'B', 'C'], [0, 10]);
    var fl = D.shape('flat', [0, 10]), bl = D.shape('bell', [0, 10]), sw = D.shape('skew', [0, 10]);
    t.state.curves = [fl, sw, bl.map(function () { return 0; })]; t.commit(t.state);
    t.setControl('variables', 'C, A, D');                  // B renamed to D
    ok.push(t.state.curves[1].join() === fl.join() && t.state.curves[2].join() === sw.join() &&
            zero(t.state.curves[0]));
    t.setControl('variables', 'C, X, D, E');
    ok.push(t.state.curves.length === 4 && t.state.curves[1].join() === bl.join() &&
            t.state.curves[3].join() === bl.join() && t.state.curves[2].join() === sw.join());
    t.setControl('variables', 'D'); ok.push(t.state.curves.length === 1 && t.state.curves[0].join() === sw.join());
    t.setControl('variables', 'D, D'); ok.push(t.state.variables.join() === 'D');
    // removal notice: only for a shaped (non-Bell, non-empty) curve; undoable
    t = mk(['A', 'B', 'C'], [0, 10]);
    var msgs = []; t._flash = function (m) { msgs.push(m); };
    t.ui.active = 1; t.action('flat');
    t.setControl('variables', 'A, B');                     // C is a Bell: no notice
    ok.push(msgs.length === 0);
    t.setControl('variables', 'A');                        // B is shaped
    ok.push(msgs.length === 1 && msgs[0].indexOf('B removed') === 0 && msgs[0].indexOf('Ctrl+Z to undo') > 0);
    t.undo(); ok.push(t.state.variables.join() === 'A,B' && t.state.curves[1][1] === 0.5);
    return ok.join(',');
  })()
"))

# Density hardening: pull reach, dead zone, stale strokes, throwing commit.
run_check("Density strokes", engine("density"), paste0(dn_script, "
  (function () {
    var D = DCR.tools.density, ok = [], t, depth, i;
    // M2: Pull uses the unclamped pointer y: press at 0.9 over 0.1, drag far above the top
    t = mk(['A'], [0, 10]);
    t.state.curves[0] = t.state.curves[0].map(function (v, j) { return j === 0 || j === 200 ? 0 : 0.1; });
    t.commit(t.state);
    stroke(t, [[50, 10], [50, 5], [50, -500]]);
    ok.push(near(t.state.curves[0][100], 1) && finite01(t));
    // M3: presses moving less than 3 px commit nothing, in both modes
    t = mk(['A'], [0, 10]); depth = t.history._index;
    ['pull', 'paint'].forEach(function (m) {
      t.ui.mode = m;
      stroke(t, [[50, 50], [51, 51], [52, 50], [50, 52]]);
    });
    ok.push(t.history._index === depth);
    t.ui.mode = 'pull';                                     // paint's first crossing frame has dt = 0
    stroke(t, [[50, 50], [50, 53]]);                       // 3 px: a real drag
    ok.push(t.history._index === depth + 1);
    t.ui.mode = 'paint';
    stroke(t, [[50, 50], [50, 52], [50, 70], [50, 70]]);   // dead zone then paint
    ok.push(t.history._index === depth + 2);
    // M1a: a pointerdown while a stale stroke exists (no end event) recovers
    t = mk(['A'], [0, 10]); depth = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: 50, clientY: 50});
    t._pointerMove({pointerId: 1, clientX: 50, clientY: 30});   // stale, moved, never released
    ok.push(t._busy === true);
    stroke(t, [[20, 50], [20, 80]]);                        // same id; and another id below
    ok.push(!t._busy && !t._stroke && t.history._index === depth + 2 && finite01(t));
    t._pointerDown({button: 0, pointerId: 7, clientX: 50, clientY: 50});
    t._pointerDown({button: 0, pointerId: 8, clientX: 50, clientY: 50});   // no hasPointerCapture: stale
    ok.push(t._stroke.id === 8);
    t._pointerUp({pointerId: 8}); t.endStroke();
    // a different pointer that is still captured is ignored
    t._dom.svg.hasPointerCapture = function () { return true; };
    t._pointerDown({button: 0, pointerId: 1, clientX: 50, clientY: 50});
    t._pointerDown({button: 0, pointerId: 2, clientX: 50, clientY: 50});
    ok.push(t._stroke.id === 1);
    t._pointerUp({pointerId: 1}); t.endStroke();
    t._dom.svg.hasPointerCapture = undefined;
    // M1b: a throwing commit in _pointerUp never leaves the engine busy
    t = mk(['A'], [0, 10]); t.setControl('n', 5);
    var real = t.commit;
    t.commit = function () { throw new Error('boom'); };
    t._pointerDown({button: 0, pointerId: 1, clientX: 50, clientY: 50});
    t._pointerMove({pointerId: 1, clientX: 50, clientY: 20});
    var threw = false;
    try { t._pointerUp({pointerId: 1}); } catch (e) { threw = true; }
    t.commit = real;
    ok.push(threw && !t._busy && !t._stroke);
    t.undo();
    ok.push(t.state.n === 1000);
    // M7: an explicit brush of 0 clamps to the minimum
    ok.push(mk(['A'], [0, 10], {brush: 0}).ui.brush === 0.005 && mk(['A'], [0, 10]).ui.brush === 0.12);
    return ok.join(',');
  })()
"))

# Histogram: stale stroke recovery and a throwing commit (same pattern as Density).
run_check("Histogram strokes", engine("histogram"), paste0(hg_script, "
  (function () {
    var ok = [], t = mk(['A'], [0, 10], 10);
    var depth = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: 5, clientY: 50});   // never released
    ok.push(t._busy === true);
    stroke(t, [[15, 40], [25, 60]]);
    ok.push(!t._busy && !t._stroke && t.history._index === depth + 2);
    t = mk(['A'], [0, 10], 10); t.setControl('n', 5);
    var real = t.commit, threw = false;
    t.commit = function () { throw new Error('boom'); };
    t._pointerDown({button: 0, pointerId: 1, clientX: 5, clientY: 50});
    try { t._pointerUp({pointerId: 1}); } catch (e) { threw = true; }
    t.commit = real;
    ok.push(threw && !t._busy);
    t.undo(); ok.push(t.state.n === 1000);
    return ok.join(',');
  })()
"))

# Density: toSpec() JSON from V8 is accepted by R's as_dcr_spec().
dn_json <- function(setup) {
  cx <- engine("density")
  cx$eval(paste0(dn_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify(T.toSpec())")
}
dn_cases <- list(
  one_variable = "var t = mk(['A'], [0, 10]); stroke(t, [[50, 50], [50, 20]]); return t;",
  three_variables = "var t = mk(['A', 'B', 'C'], [0, 10]); stroke(t, [[30, 50], [30, 70]]);
    t.action('select-2'); t.action('skew'); t.action('select-3'); t.action('flat'); return t;",
  offset_xlim = "var t = mk(['A'], [1000, 1010]); stroke(t, [[40, 50], [40, 80]]); return t;",
  after_xlim = "var t = mk(['A', 'B'], [0, 10]); t.setControl('xlim', [-5, 20]);
    t.setControl('xlim', [3, 8]); return t;",
  all_zero_second = "var t = mk(['A', 'B'], [0, 10]);
    t.state.curves[1] = t.state.curves[1].map(function () { return 0; }); t.commit(t.state); return t;",
  disjoint_xlim = "var t = mk(['A'], [0, 10]); t.setControl('xlim', [20, 30]); return t;"
)
for (nm in names(dn_cases)) {
  spec <- tryCatch(as_dcr_spec(jsonlite::fromJSON(dn_json(dn_cases[[nm]]))),
                   error = function(e) {
                     message("Density round trip failed (", nm, "): ", conditionMessage(e))
                     quit(status = 1)
                   })
  stopifnot(inherits(spec, "dcr_spec"), spec$n == 1000, is.matrix(spec$curves),
            ncol(spec$curves) == 201L, all(spec$curves >= 0), all(spec$curves <= 1),
            all(spec$curves[, 1] == 0), all(spec$curves[, 201] == 0))
  if (nm == "disjoint_xlim") {
    stopifnot(spec_is_empty(spec))
  } else {
    stopifnot(!spec_is_empty(spec))
    df <- sample_spec(spec, 50)
    stopifnot(nrow(df) == 50L, all(is.finite(unlist(df))),
              all(unlist(df) >= spec$xlim[1]), all(unlist(df) <= spec$xlim[2]))
    if (nm == "all_zero_second") {
      stopifnot(identical(attr(df, "dropped"), "B"), ncol(df) == 1L)
    }
  }
}

# Density: Done flushes the sidebar (mode / brush / n / xlim / variables).
run_check("Density Done flush", engine(c("density")), paste0(flush_script, "
  (function () {
    var d = new DCR.tools.density(el(), {variables: ['V1', 'V2', 'V3']});
    d._flash = function () {};
    sidebar = {active: '1', variables: 'V1, V2', mode: 'paint', brush: 0.3, n: 250, xlim: [0, 20]};
    var s = doneSpec(d);
    return [s !== null && s.n === 250 && s.variables.join() === 'V1,V2' && s.xlim[1] === 20 &&
            s.curves.length === 2 && d.ui.mode === 'paint' && d.ui.brush === 0.3,
            // invalid values: ignored, Done still sends
            (function () {
              sidebar = {variables: 'A, A', xlim: ['', 3], n: 0, brush: 'big', mode: 'spray'};
              var s2 = doneSpec(d);
              return s2 !== null && s2.variables.join() === 'V1,V2' && s2.n === 250;
            })()].join(',');
  })()
"))

# Bivariate: geometry conversions, Handles mode, stroke hardening, autofit,
# limits, groups, and toSpec() accepted by R.
bv_script <- "
  function mk(groups, o) {
    var opts = {groups: groups, n: 200, xlim: [0, 10], ylim: [0, 10]};
    for (var k in (o || {})) opts[k] = o[k];
    var t = new DCR.tools.bivariate({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }}, opts);
    // fake 100 x 100 px plot: 1 px = 0.1 data unit for the default limits
    t._geo = {left: 0, top: 0, width: 100, height: 100, k: 10};
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    t._flash = function (m) { t._flashed = (t._flashed || []).concat([m]); };
    return t;
  }
  function px(t, x, y) {      // data -> client px with the fake geometry
    var L = t._geo, s = t.state;
    return [L.left + (x - s.xlim[0]) * L.k, L.top + L.height - (y - s.ylim[0]) * L.k];
  }
  function stroke(t, pts) {
    t._pointerDown({button: 0, pointerId: 1, clientX: pts[0][0], clientY: pts[0][1]});
    pts.slice(1).forEach(function (p) {
      t._pointerMove({pointerId: 1, clientX: p[0], clientY: p[1]});
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
  }
  function near(a, b, e) { return Math.abs(a - b) < (e || 1e-9); }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function copyOf(x) { return JSON.parse(JSON.stringify(x)); }
  function B() { return DCR.tools.bivariate; }
  function finite(t) {
    return t.state.ell.every(function (e) {
      return [e.mx, e.my, e.s1, e.s2, e.th].every(isFinite) && e.s1 > 0 && e.s2 > 0;
    });
  }
  function handle(t, which) {
    var e = t.state.ell[t.activeIndex()], h = t._handles(e);
    return px(t, h[which].x, h[which].y);
  }
  function centre(t) {
    var e = t.state.ell[t.activeIndex()];
    return px(t, e.mx, e.my);
  }
"
run_check("Bivariate geometry", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [];
    // marginal <-> ellipse: circle, elongated, all rho
    var cases = [];
    [-0.9, -0.5, 0, 0.5, 0.9].forEach(function (r) {
      cases.push({mean_x: 1, mean_y: -2, sd_x: 1, sd_y: 1, rho: r});
      cases.push({mean_x: 3, mean_y: 4, sd_x: 10, sd_y: 1, rho: r});
      cases.push({mean_x: 3, mean_y: 4, sd_x: 0.5, sd_y: 2, rho: r});
    });
    var good = true;
    cases.forEach(function (m) {
      var e = B().fromMarginal(m), m2 = B().toMarginal(e);
      ['mean_x', 'mean_y', 'sd_x', 'sd_y', 'rho'].forEach(function (k) {
        if (!near(m[k], m2[k]) || !isFinite(m2[k])) good = false;
      });
      if (!(e.s1 >= e.s2 && e.s2 > 0)) good = false;
    });
    ok.push(good);
    // ellipse -> marginal -> ellipse: same marginals for any angle
    good = true;
    [0, Math.PI / 2, -Math.PI / 2, Math.PI, 3, 100].forEach(function (th) {
      [[2, 1], [1, 1], [5, 0.01]].forEach(function (s) {
        var e = {mx: 1, my: 2, s1: s[0], s2: s[1], th: th};
        var m = B().toMarginal(e), m2 = B().toMarginal(B().fromMarginal(m));
        ['mean_x', 'mean_y', 'sd_x', 'sd_y', 'rho'].forEach(function (k) {
          if (!near(m[k], m2[k], 1e-9) || !isFinite(m2[k])) good = false;
        });
      });
    });
    ok.push(good);
    // |rho| is clamped
    ok.push(B().toMarginal({mx: 0, my: 0, s1: 100, s2: 0.001, th: 0.7}).rho === 0.999 &&
            B().fromMarginal({mean_x: 0, mean_y: 0, sd_x: 1, sd_y: 1, rho: 5}).s2 > 0);
    // initial layout
    var one = B().initial(['A'], [0, 10], [0, 10]);
    ok.push(one.length === 1 && near(one[0].mx, 5) && near(one[0].my, 5) &&
            near(B().toMarginal(one[0]).sd_x, 1) && near(B().toMarginal(one[0]).rho, 0.5));
    var three = B().initial(['A', 'B', 'C'], [0, 20], [0, 10]);   // m = 10, centre (10, 5)
    ok.push(three.length === 3 &&
            three.every(function (e) { return near(Math.hypot(e.mx - 10, e.my - 5), 2.5); }) &&
            near(three[0].mx, 10) && near(three[0].my, 7.5) &&         // first at the top
            three[1].mx > 10 && three[1].my < 5 &&                     // clockwise: right, below
            three[2].mx < 10 && three[2].my < 5 &&
            three.every(function (e) { return near(B().toMarginal(e).sd_x, 1) && near(B().toMarginal(e).sd_y, 1); }) &&
            [0, 1, 2].every(function (i) { return near(B().toMarginal(three[i]).rho, [0.5, -0.5, 0][i]); }));
    // fitLimits: never shrinks, rounds only moved ends outward
    ok.push(B().fitLimits([0, 10], 2, 8).join() === '0,10' &&
            B().fitLimits([0, 10], -1.3, 8).join() === '-5,10' &&
            B().fitLimits([0, 10], 2, 10.2).join() === '0,15' &&
            B().fitLimits([0, 10], NaN, 12).join() === '0,15' &&
            B().fitLimits([1000, 1010], 995.5, 1010)[0] <= 995.5);
    // contains
    var e1 = B().initial(['A'], [0, 10], [0, 10]);
    ok.push(B().contains([0, 10], [0, 10], e1) && !B().contains([5, 10], [0, 10], e1) &&
            B().contains([-100, 100], [-100, 100], e1));
    return ok.join(',');
  })()
"))

run_check("Bivariate handles", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [], t, d0, e, h, c, r, a, a0, pts, k, i, th0, s10, s20, th1;
    // centre drag: move, one entry, undo restores
    t = mk(['A']); d0 = t.history._index;
    stroke(t, [[50, 50], [60, 40], [70, 30]]);
    ok.push(near(t.state.ell[0].mx, 7) && near(t.state.ell[0].my, 7) &&
            t.history._index === d0 + 1);
    t.undo();
    ok.push(near(t.state.ell[0].mx, 5) && near(t.state.ell[0].my, 5));
    // the mean is clamped to the view
    t = mk(['A']); t.ui.autofit = false; stroke(t, [[50, 50], [200, -50]]);
    ok.push(near(t.state.ell[0].mx, 10) && near(t.state.ell[0].my, 10));

    // major handle: +90 degrees around the centre rotates th by +90, s1 unchanged
    t = mk(['A']); e = t.state.ell[0]; th0 = e.th; s10 = e.s1; s20 = e.s2;
    h = handle(t, 'major'); c = centre(t);
    r = Math.hypot(h[0] - c[0], h[1] - c[1]);
    a0 = Math.atan2(-(h[1] - c[1]), h[0] - c[0]); pts = [[h[0], h[1]]];
    for (k = 1; k <= 18; k++) {
      a = a0 + k * (Math.PI / 2) / 18;
      pts.push([c[0] + r * Math.cos(a), c[1] - r * Math.sin(a)]);
    }
    stroke(t, pts);
    e = t.state.ell[0];
    ok.push(near(e.th, th0 + Math.PI / 2, 1e-6) && near(e.s1, s10, 1e-6) && near(e.s2, s20));
    // no jump at the grab: press off the handle centre (inside the hit radius),
    // move outward along the same ray: th is kept (only the angular delta counts)
    t = mk(['A']); e = t.state.ell[0]; th0 = e.th;
    h = handle(t, 'major'); c = centre(t);
    var gx = h[0] + 1.5, gy = h[1] + 1.5;
    var ga = Math.atan2(-(gy - c[1]), gx - c[0]);
    stroke(t, [[gx, gy], [gx + 4 * Math.cos(ga), gy - 4 * Math.sin(ga)]]);
    ok.push(near(t.state.ell[0].th, th0, 1e-9) && near(t.state.ell[0].s1, s10 + 0.4, 1e-9));
    // rotation through +-180 never flips an axis: s1 stays, th accumulates 450 degrees
    t = mk(['A']); e = t.state.ell[0]; h = handle(t, 'major'); c = centre(t);
    r = Math.hypot(h[0] - c[0], h[1] - c[1]); a0 = Math.atan2(-(h[1] - c[1]), h[0] - c[0]);
    pts = [[h[0], h[1]]];
    for (k = 1; k <= 40; k++) {
      a = a0 + k * (2 * Math.PI * 1.25) / 40;
      pts.push([c[0] + r * Math.cos(a), c[1] - r * Math.sin(a)]);
    }
    th0 = e.th; stroke(t, pts);
    e = t.state.ell[0];
    ok.push(near(e.th, th0 + 2.5 * Math.PI, 1e-6) && near(e.s1, s10, 1e-6) && finite(t));

    // minor handle: s2 changes, th and s1 do not
    t = mk(['A']); e = t.state.ell[0]; th1 = e.th;
    h = handle(t, 'minor'); c = centre(t);
    var dir = [h[0] - c[0], h[1] - c[1]], len = Math.hypot(dir[0], dir[1]);
    stroke(t, [[h[0], h[1]], [h[0] + dir[0] / len * 10, h[1] + dir[1] / len * 10]]);
    e = t.state.ell[0];
    ok.push(near(e.s2, s20 + 1, 1e-6) && near(e.th, th1) && near(e.s1, s10));
    // through the centre exactly: the minimum, never <= 0; s1 and th unchanged
    t = mk(['A']); h = handle(t, 'minor'); c = centre(t);
    stroke(t, [[h[0], h[1]], [c[0], c[1]]]);
    e = t.state.ell[0];
    ok.push(e.s2 === 0.05 && near(e.s1, s10) && near(e.th, th1));
    // and past it: stays at the minimum (no mirroring), further out too; no swap
    t = mk(['A']); h = handle(t, 'minor'); c = centre(t);
    stroke(t, [[h[0], h[1]], [c[0], c[1]], [2 * c[0] - h[0], 2 * c[1] - h[1]]]);
    e = t.state.ell[0];
    ok.push(e.s2 === 0.05 && near(e.s1, s10) && near(e.th, th1));
    t = mk(['A']); h = handle(t, 'minor'); c = centre(t);
    stroke(t, [[h[0], h[1]], [c[0], c[1]], [3 * c[0] - 2 * h[0], 3 * c[1] - 2 * h[1]]]);
    e = t.state.ell[0];
    ok.push(e.s2 === 0.05 && near(e.s1, s10) && near(e.th, th1));
    // huge pull: capped by SMAX and by the rho bound s1 <= s2 / 0.02237
    t = mk(['A']); h = handle(t, 'major'); stroke(t, [[h[0], h[1]], [h[0] + 1e7, h[1]]]);
    e = t.state.ell[0];
    ok.push(e.s1 <= 100 && e.s1 <= e.s2 / 0.02237 + 1e-9 && e.s1 > 10 && finite(t));
    // M-1: extreme stretches at th = pi/4 never need toMarginal's rho clamp
    function rawRho(e) {
      var c = Math.cos(e.th), s = Math.sin(e.th), a = e.s1 * e.s1, b = e.s2 * e.s2;
      return (a - b) * s * c / Math.sqrt((a * c * c + b * s * s) * (a * s * s + b * c * c));
    }
    t = mk(['A']); t.state.ell[0] = {mx: 5, my: 5, s1: 100, s2: 100, th: Math.PI / 4}; t.commit(t.state);
    t.state.xlim = [-100, 100]; t.state.ylim = [-100, 100]; t.commit(t.state);
    t._geo = {left: 0, top: 0, width: 100, height: 100, k: 0.5};
    h = handle(t, 'minor'); c = centre(t);
    stroke(t, [[h[0], h[1]], [c[0], c[1]]]);                         // minor to the minimum
    ok.push(Math.abs(rawRho(t.state.ell[0])) <= 0.999 && t.state.ell[0].s2 >= 0.02237 * 100 - 1e-9);
    h = handle(t, 'major'); c = centre(t);
    stroke(t, [[h[0], h[1]], [c[0], c[1]]]);                         // major to the minimum
    ok.push(Math.abs(rawRho(t.state.ell[0])) <= 0.999 && finite(t) &&
            t.state.ell[0].s1 >= 0.02237 * t.state.ell[0].s2 - 1e-9);
    // I-4: a thin ellipse's centre is still grabbable (nearest of the three wins)
    t = mk(['A']); t.state.ell[0] = {mx: 5, my: 5, s1: 2, s2: 0.02, th: 0.3}; t.commit(t.state);
    c = centre(t);
    stroke(t, [[c[0], c[1]], [c[0] + 10, c[1]]]);
    ok.push(near(t.state.ell[0].mx, 6) && t.state.ell[0].s2 === 0.02 && near(t.state.ell[0].s1, 2));
    // I-5: autofit off: a handle can never be stretched out of the view
    t = mk(['A']); t.setControl('autofit', false);
    h = handle(t, 'major'); stroke(t, [[h[0], h[1]], [h[0] + 1e4, h[1]]]);
    var hm = t._handles(t.state.ell[0]);
    ok.push(hm.major.x <= 10 + 1e-9 && hm.major.y <= 10 + 1e-9 && hm.major.x >= -1e-9 && finite(t));
    h = handle(t, 'minor'); stroke(t, [[h[0], h[1]], [h[0] - 1e4, h[1] - 1e4]]);
    hm = t._handles(t.state.ell[0]);
    ok.push(hm.minor.x >= -1e-9 && hm.minor.y >= -1e-9 && hm.minor.x <= 10 + 1e-9 &&
            hm.minor.y <= 10 + 1e-9 && finite(t));
    // M-2: a major drag through the centre does not spin th with tiny vectors
    t = mk(['A']); th0 = t.state.ell[0].th; c = centre(t); h = handle(t, 'major');
    var loop = [[h[0], h[1]]];
    for (k = 0; k <= 8; k++) {
      a = k * Math.PI / 4;
      loop.push([c[0] + 0.05 * Math.cos(a), c[1] + 0.05 * Math.sin(a)]);   // ~0.005 data units
    }
    loop.push([h[0], h[1]]);
    stroke(t, loop);
    ok.push(near(t.state.ell[0].th, th0, 1e-9) && finite(t));
    // I-A: with autofit off, moving the centre never changes s1 / s2 (one stroke, two strokes)
    t = mk(['A']); t.setControl('autofit', false); e = copyOf(t.state.ell[0]); c = centre(t);
    stroke(t, [[c[0], c[1]], [100, c[1]], [c[0], c[1]]]);
    ok.push(t.state.ell[0].s1 === e.s1 && t.state.ell[0].s2 === e.s2 && t.state.ell[0].th === e.th);
    t = mk(['A']); t.setControl('autofit', false); c = centre(t);
    stroke(t, [[c[0], c[1]], [100, 100]]);
    ok.push(near(t.state.ell[0].mx, 10) && t.state.ell[0].s1 === e.s1 && t.state.ell[0].s2 === e.s2);
    c = centre(t); stroke(t, [[c[0], c[1]], [50, 50]]);
    ok.push(t.state.ell[0].s1 === e.s1 && t.state.ell[0].s2 === e.s2 && t.state.ell[0].th === e.th);
    // near-circular ellipse: many rotations through the centre stay finite
    t = mk(['A']); t.state.ell[0] = {mx: 5, my: 5, s1: 1, s2: 1, th: 0}; t.commit(t.state);
    for (i = 0; i < 30; i++) {
      h = handle(t, 'major'); c = centre(t);
      stroke(t, [[h[0], h[1]], [c[0] + 15, c[1] + 9 * (i % 3)], [c[0], c[1]], [c[0] - 20, c[1] - 7]]);
    }
    ok.push(finite(t) && isFinite(B().toMarginal(t.state.ell[0]).rho));
    return ok.join(',');
  })()
"))

run_check("Bivariate strokes", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [], t, d0, i, h, c, e, q;
    // 200 rapid clicks on the centre, both handles and empty canvas: no history, no freeze
    t = mk(['A', 'B']); d0 = t.history._index;
    var targets = [centre(t), handle(t, 'major'), handle(t, 'minor'), [3, 97], [99, 1]];
    for (i = 0; i < 200; i++) {
      q = targets[i % targets.length];
      t._pointerDown({button: 0, pointerId: 1, clientX: q[0], clientY: q[1]});
      if (i % 3 === 0) t._pointerMove({pointerId: 1, clientX: q[0] + 1, clientY: q[1] - 1});
      t._pointerUp({pointerId: 1}); t.endStroke();
    }
    ok.push(t.history._index === d0 && !t._busy && !t._stroke && finite(t));
    // 3 px is a real drag; 2.9 px is not
    h = handle(t, 'major');
    stroke(t, [[h[0], h[1]], [h[0] + 2.9, h[1]]]);
    ok.push(t.history._index === d0);
    c = centre(t);
    stroke(t, [[c[0], c[1]], [c[0] + 3, c[1]]]);
    ok.push(t.history._index === d0 + 1);
    // a real drag is one entry, undo restores
    t = mk(['A']); d0 = t.history._index; e = copyOf(t.state.ell[0]);
    h = handle(t, 'major');
    stroke(t, [[h[0], h[1]], [h[0] + 10, h[1] + 5], [h[0] + 20, h[1] - 8], [h[0] + 15, h[1]]]);
    ok.push(t.history._index === d0 + 1 && !same(t.state.ell[0], e));
    t.undo();
    ok.push(same(t.state.ell[0], e));
    // stale stroke (no end event) recovers on the next press
    t = mk(['A']); d0 = t.history._index; c = centre(t);
    t._pointerDown({button: 0, pointerId: 1, clientX: c[0], clientY: c[1]});
    t._pointerMove({pointerId: 1, clientX: c[0] + 20, clientY: c[1]});
    ok.push(t._busy === true);
    c = centre(t);
    stroke(t, [[c[0], c[1]], [c[0], c[1] + 20]]);
    ok.push(!t._busy && !t._stroke && t.history._index === d0 + 2 && finite(t));
    c = centre(t);
    t._pointerDown({button: 0, pointerId: 7, clientX: c[0], clientY: c[1]});
    t._pointerDown({button: 0, pointerId: 8, clientX: c[0], clientY: c[1]});   // no hasPointerCapture: stale
    ok.push(t._stroke && t._stroke.id === 8);
    t._pointerUp({pointerId: 8}); t.endStroke();
    // a different pointer that is still captured is ignored
    t._dom.svg.hasPointerCapture = function () { return true; };
    t._pointerDown({button: 0, pointerId: 1, clientX: c[0], clientY: c[1]});
    t._pointerDown({button: 0, pointerId: 2, clientX: c[0], clientY: c[1]});
    ok.push(t._stroke.id === 1);
    t._pointerUp({pointerId: 1}); t.endStroke();
    t._dom.svg.hasPointerCapture = undefined;
    // a throwing commit never leaves the engine busy
    t = mk(['A']); t.setControl('n', 5);
    var real = t.commit, threw = false;
    t.commit = function () { throw new Error('boom'); };
    c = centre(t);
    t._pointerDown({button: 0, pointerId: 1, clientX: c[0], clientY: c[1]});
    t._pointerMove({pointerId: 1, clientX: c[0] + 30, clientY: c[1]});
    try { t._pointerUp({pointerId: 1}); } catch (err) { threw = true; }
    t.commit = real;
    ok.push(threw && !t._busy && !t._stroke);
    t.undo(); ok.push(t.state.n === 200);
    // clicking another group's interior selects it without history
    t = mk(['A', 'B']); d0 = t.history._index;
    var b = t.state.ell[1], pb = px(t, b.mx, b.my);
    t._pointerDown({button: 0, pointerId: 1, clientX: pb[0], clientY: pb[1]});
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.ui.active === 1 && t.history._index === d0 && !t._busy && !t._stroke);
    t.action('select-1'); ok.push(t.ui.active === 0);
    // controls queued during a stroke apply after it, as separate entries
    t = mk(['A']); d0 = t.history._index; c = centre(t);
    t._pointerDown({button: 0, pointerId: 1, clientX: c[0], clientY: c[1]});
    t._pointerMove({pointerId: 1, clientX: c[0] + 20, clientY: c[1]});
    t.receiveControl('n', 300);
    ok.push(t.state.n === 200);
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.state.n === 300 && t.history._index === d0 + 2);
    return ok.join(',');
  })()
"))

run_check("Bivariate gestures", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [], t, d0, i, e, c, q, st;
    var Z = function (e, x, y) { return B().zoneOf(e, {x: x, y: y}, 1); };
    // zoneOf: axis-aligned ellipse (sd 1 and 0.5): 2-sigma contour at 2 and 1,
    // ring 0.3 outside it, stretch up to 1.0 outside it
    var E = {mx: 5, my: 5, s1: 1, s2: 0.5, th: 0};
    ok.push(Z(E, 5, 5) === 'in' && Z(E, 6.9, 5) === 'in' && Z(E, 5, 5.9) === 'in');
    ok.push(Z(E, 7.15, 5) === 'ring' && Z(E, 5, 6.15) === 'ring');
    ok.push(Z(E, 7.6, 5) === 'stretch' && Z(E, 5, 6.6) === 'stretch');
    ok.push(Z(E, 8.5, 5) === null && Z(E, 5, 7.5) === null);
    // circle of sd 1: ring 2..2.3, stretch 2.3..3, in every direction
    var C = {mx: 5, my: 5, s1: 1, s2: 1, th: 0.7};
    ok.push([0, 1, 2, 3, 4, 5].every(function (k) {
      var a = k * 1.1, f = function (r) { return Z(C, 5 + r * Math.cos(a), 5 + r * Math.sin(a)); };
      return f(1.9) === 'in' && f(2.15) === 'ring' && f(2.6) === 'stretch' && f(3.1) === null;
    }));
    // rotated ellipse (th = 60 deg): zones follow the axes
    var R = {mx: 5, my: 5, s1: 1, s2: 0.5, th: Math.PI / 3}, ca = Math.cos(R.th), sa = Math.sin(R.th);
    ok.push(Z(R, 5 + 1.9 * ca, 5 + 1.9 * sa) === 'in' && Z(R, 5 + 2.15 * ca, 5 + 2.15 * sa) === 'ring' &&
            Z(R, 5 + 2.6 * ca, 5 + 2.6 * sa) === 'stretch' &&
            Z(R, 5 - 2.6 * sa, 5 + 2.6 * ca) === null &&
            Z(R, 5 - 1.6 * sa, 5 + 1.6 * ca) === 'stretch');
    // the zone scales with the unit u
    ok.push(B().zoneOf(E, {x: 8.5, y: 5}, 2) === 'stretch' && B().zoneOf(E, {x: 7.3, y: 5}, 2) === 'ring');

    function gt(o, ell) {
      var t = mk(['A'], o); t.ui.mode = 'gestures';
      if (ell) t.state.ell[0] = copyOf(ell);
      t._dom.svg.style = {};
      return t;
    }
    function setEll(t, i, ell) {      // a committed (undoable) ellipse
      var next = copyOf(t.state); next.ell[i] = copyOf(ell); t.commit(next);
    }
    function down(t, x, y, o) {
      var q = px(t, x, y), ev = {button: 0, pointerId: 1, clientX: q[0], clientY: q[1]};
      for (var k in (o || {})) ev[k] = o[k];
      t._pointerDown(ev);
    }
    function move(t, x, y) { var q = px(t, x, y); t._pointerMove({pointerId: 1, clientX: q[0], clientY: q[1]}); }
    function up(t) { t._pointerUp({pointerId: 1}); t.endStroke(); }
    function drag(t, from, tos, o) {
      down(t, from[0], from[1], o);
      tos.forEach(function (p) { move(t, p[0], p[1]); });
      up(t);
    }

    // stretch grabbed near the major axis changes only s1: outward grows,
    // inward shrinks, relative to the grab (no jump)
    t = gt({}, E); d0 = t.history._index;
    drag(t, [7.6, 5], [[8.9, 5.0]]);
    e = t.state.ell[0];
    ok.push(near(e.s1, 1.5, 1e-6) && e.s2 === 0.5 && e.th === 0 && e.mx === 5 && e.my === 5 &&
            t.history._index === d0 + 1);
    t = gt({}, E);
    drag(t, [7.6, 5], [[6.3, 5]]);
    ok.push(near(t.state.ell[0].s1, 0.5, 1e-6) && t.state.ell[0].s2 === 0.5);
    // grab on the far (left) side: outward is still growth
    t = gt({}, E);
    drag(t, [2.4, 5], [[1.1, 5]]);
    ok.push(near(t.state.ell[0].s1, 1.5, 1e-6) && t.state.ell[0].s2 === 0.5);
    // off-axis grab: the pointer's projection on the axis is what counts
    t = gt({}, E);
    drag(t, [7.6, 5.4], [[8.9, 6.0]]);
    ok.push(near(t.state.ell[0].s1, 1.5, 1e-6) && t.state.ell[0].th === 0);
    // through the centre and out the other side: SMIN (0.05), never <= 0, never mirrors
    t = gt({}, E);
    drag(t, [7.6, 5], [[5, 5], [3, 5], [1, 5]]);
    e = t.state.ell[0];
    ok.push(near(e.s1, 0.05, 1e-9) && e.s2 === 0.5 && e.th === 0 && finite(t));
    // grabbed near the minor axis: only s2 changes
    t = gt({}, E);
    drag(t, [5, 6.6], [[5, 7.4]]);
    e = t.state.ell[0];
    ok.push(near(e.s2, 0.5 * 2.4 / 1.6, 1e-6) && e.s1 === 1 && e.th === 0);
    t = gt({}, E);
    drag(t, [5, 3.4], [[5, 4.2]]);
    e = t.state.ell[0];
    ok.push(near(e.s2, 0.5 * 0.8 / 1.6, 1e-6) && e.s1 === 1);
    t = gt({}, E);
    drag(t, [5, 6.6], [[5, 5], [5, 2], [5, 0.5]]);
    e = t.state.ell[0];
    ok.push(near(e.s2, 0.05, 1e-9) && e.s1 === 1 && finite(t));
    // rotated ellipse: stretch follows the ellipse axes
    t = gt({}, R);
    drag(t, [5 + 2.6 * ca, 5 + 2.6 * sa], [[5 + 3.9 * ca, 5 + 3.9 * sa]]);
    e = t.state.ell[0];
    ok.push(near(e.s1, 1.5, 1e-6) && e.s2 === 0.5 && e.th === R.th);
    // the rho limit holds: s2 cannot go below RATIO * s1
    t = gt({}, {mx: 5, my: 5, s1: 4, s2: 2, th: 0});
    drag(t, [5, 5 + 2 * 2 + 0.5], [[5, 5.5], [5, 5]]);
    e = t.state.ell[0];
    ok.push(e.s2 >= 4 * 0.02237 - 1e-12 && e.s2 > 0.05 - 1e-12 && Math.abs(B().toMarginal(e).rho) <= 0.999 + 1e-9);

    // first move right after the dead zone: nothing beyond the pointer delta
    t = gt({}, E);
    down(t, 7.6, 5); move(t, 7.6 + 0.2, 5);          // 2 px: still a click
    ok.push(t.state.ell[0].s1 === 1);
    move(t, 7.6 + 0.3, 5);                           // 3 px: first real move
    ok.push(near(t.state.ell[0].s1, 2.9 / 2.6, 1e-9)); up(t);
    t = gt({}, E);
    down(t, 5, 6.6); move(t, 5, 6.6 + 0.3);
    ok.push(near(t.state.ell[0].s2, 0.5 * 1.9 / 1.6, 1e-9) && t.state.ell[0].s1 === 1); up(t);

    // ring drag: rotates by the pointer's angular delta, no sd change
    var th0 = Math.PI / 6, Rg = {mx: 5, my: 5, s1: 1, s2: 0.5, th: th0};
    t = gt({}, Rg);
    // find a ring point for this ellipse in direction 0.2 rad
    var rr = null;
    for (var r = 0.5; r < 6; r += 0.01) {
      if (Z(Rg, 5 + r * Math.cos(0.2), 5 + r * Math.sin(0.2)) === 'ring') { rr = r + 0.05; break; }
    }
    function at(a, rad) { return [5 + rad * Math.cos(a), 5 + rad * Math.sin(a)]; }
    drag(t, at(0.2, rr), [at(0.2 + Math.PI / 4, rr)]);
    e = t.state.ell[0];
    ok.push(near(e.th, th0 + Math.PI / 4, 1e-6) && e.s1 === 1 && e.s2 === 0.5 && e.mx === 5);
    // multi-turn accumulation (+405 deg in 45 deg steps), no flip
    t = gt({}, Rg);
    var steps = []; for (i = 1; i <= 9; i++) steps.push(at(0.2 + i * Math.PI / 4, rr));
    drag(t, at(0.2, rr), steps);
    ok.push(near(t.state.ell[0].th, th0 + 9 * Math.PI / 4, 1e-6));
    // and the other way (-270 deg)
    t = gt({}, Rg);
    steps = []; for (i = 1; i <= 6; i++) steps.push(at(0.2 - i * Math.PI / 4, rr));
    drag(t, at(0.2, rr), steps);
    ok.push(near(t.state.ell[0].th, th0 - 6 * Math.PI / 4, 1e-6) && t.state.ell[0].s1 === 1);
    // the angle freezes while the pointer is near the centre
    t = gt({}, Rg);
    drag(t, at(0.2, rr), [at(0.2 + 4, 0.05), at(0.2 + Math.PI / 2, rr)]);
    ok.push(near(t.state.ell[0].th, th0 + Math.PI / 2, 1e-6));
    // a near-circular ellipse rotates and stays finite
    t = gt({}, {mx: 5, my: 5, s1: 1, s2: 0.999, th: 0});
    drag(t, at(0.1, 2.15), [at(1.7, 2.15), at(3.3, 2.15), at(4.9, 2.15), at(6.5, 2.15)]);
    ok.push(finite(t) && t.state.ell[0].s1 === 1 && t.state.ell[0].s2 === 0.999);
    // Shift + stretch rotates (decided at pointerdown); no Shift: stretches
    t = gt({}, E);
    drag(t, [7.6, 5], [[5, 7.6]], {shiftKey: true});
    e = t.state.ell[0];
    ok.push(near(e.th, Math.PI / 2, 1e-6) && e.s1 === 1 && e.s2 === 0.5);
    t = gt({}, E);
    down(t, 7.6, 5, {shiftKey: true}); up(t);
    down(t, 7.6, 5); move(t, 8.9, 5); up(t);
    ok.push(near(t.state.ell[0].s1, 1.5, 1e-6) && t.state.ell[0].th === 0);

    // inside = move (as Handles centre): relative to the grab, clamped to the view
    t = gt({}, E);
    drag(t, [5.5, 5.2], [[6.5, 6.2]]);
    e = t.state.ell[0];
    ok.push(near(e.mx, 6, 1e-6) && near(e.my, 6, 1e-6) && e.s1 === 1 && e.s2 === 0.5);
    t = gt({}, E);
    t.ui.autofit = false;
    drag(t, [5, 5], [[20, 5]]);
    ok.push(t.state.ell[0].mx === 10 && same(t.state.xlim, [0, 10]));
    t = gt({}, E);                                    // autofit on: the view grows to hold it
    drag(t, [5, 5], [[20, 5]]);
    ok.push(t.state.ell[0].mx === 10 && t.state.xlim[1] > 10 &&
            B().contains(t.state.xlim, t.state.ylim, t.state.ell));

    // autofit off: a stretched sd is capped so the grabbed side's ring stays in view
    // ((reach - 0.15 u) / 2); reach is measured on the grabbed side
    var E7 = {mx: 7, my: 5, s1: 1, s2: 0.5, th: 0};
    t = gt({}, E7); t.ui.autofit = false;
    drag(t, [9.6, 5], [[30, 5]]);
    ok.push(near(t.state.ell[0].s1, (3 - 0.15) / 2, 1e-9) && t.state.ell[0].s2 === 0.5);
    t = gt({}, E7); t.ui.autofit = false;
    drag(t, [4.4, 5], [[-20, 5]]);                    // far side: reach 7 to the left, not 3
    ok.push(near(t.state.ell[0].s1, (7 - 0.15) / 2, 1e-9));
    t = gt({}, E7); t.ui.autofit = false;
    drag(t, [7, 6.6], [[7, 40]]);                     // minor axis upwards: reach 5
    ok.push(near(t.state.ell[0].s2, (5 - 0.15) / 2, 1e-9) && t.state.ell[0].s1 === 1);
    t = gt({}, E7); t.ui.autofit = false;
    drag(t, [9.6, 5], [[8.3, 5]]);                    // shrinking is not capped
    ok.push(near(t.state.ell[0].s1, 1 * 1.3 / 2.6, 1e-9));
    // autofit on: stretching past the view grows the limits in the same entry; one undo restores both
    t = gt({}, E); setEll(t, 0, E); d0 = t.history._index;
    var lim0 = copyOf(t.state.xlim);
    drag(t, [7.6, 5], [[12, 5]]);
    ok.push(t.history._index === d0 + 1 && t.state.xlim[1] > 10 && near(t.state.ell[0].s1, 7 / 2.6, 1e-9) &&
            B().contains(t.state.xlim, t.state.ylim, t.state.ell));
    t.undo();
    ok.push(same(t.state.xlim, lim0) && same(t.state.ell[0], E) && t.history._index === d0);

    // 200 presses without movement in each zone, on empty canvas and in another group: no history, no freeze
    t = mk(['A', 'B']); t.ui.mode = 'gestures'; t._dom.svg.style = {};
    t.state.ell[0] = {mx: 3, my: 3, s1: 1, s2: 0.5, th: 0};
    t.state.ell[1] = {mx: 8, my: 8, s1: 0.5, s2: 0.5, th: 0};
    d0 = t.history._index;
    var pts = [[3, 3], [5.15, 3], [5.6, 3], [3, 4.15], [3, 4.6], [9.5, 1], [8, 8]];
    for (i = 0; i < 200; i++) {
      q = pts[i % pts.length];
      down(t, q[0], q[1], i % 5 === 0 ? {shiftKey: true} : {});
      if (i % 3 === 0) { var m = px(t, q[0], q[1]); t._pointerMove({pointerId: 1, clientX: m[0] + 1, clientY: m[1] - 1}); }
      up(t);
      t.ui.active = 0;
    }
    ok.push(t.history._index === d0 && !t._busy && !t._stroke && finite(t));
    // 2.9 px in each zone commits nothing
    [[3, 3], [5.15, 3], [5.6, 3]].forEach(function (p) {
      var a = px(t, p[0], p[1]);
      stroke(t, [[a[0], a[1]], [a[0] + 2.9, a[1]]]);
    });
    ok.push(t.history._index === d0);
    // a real drag in each zone is exactly one entry; each undo restores the shape before that drag
    setEll(t, 0, {mx: 3, my: 3, s1: 1, s2: 0.5, th: 0}); d0 = t.history._index;
    var sh0 = copyOf(t.state.ell[0]);
    drag(t, [5.6, 3], [[6.0, 3], [6.5, 3]]);                 // stretch
    var sh1 = copyOf(t.state.ell[0]);
    drag(t, [3, 3], [[3.5, 3.2]]);                           // move
    var sh2 = copyOf(t.state.ell[0]);
    ok.push(t.history._index === d0 + 2 && !same(sh0, sh1) && !same(sh1, sh2));
    t.undo(); ok.push(same(t.state.ell[0], sh1));
    t.undo(); ok.push(same(t.state.ell[0], sh0) && t.history._index === d0);
    // in Gestures mode the handles are not hit; in Handles mode the ring/stretch zones are not
    t = mk(['A']); t.ui.mode = 'gestures'; t._dom.svg.style = {}; t.state.ell[0] = copyOf(E);
    d0 = t.history._index;
    var hq = handle(t, 'major');
    t._pointerDown({button: 0, pointerId: 1, clientX: hq[0], clientY: hq[1]});
    ok.push(t._stroke && t._stroke.kind === 'move');           // major handle is inside the 2 sigma contour
    t._pointerUp({pointerId: 1}); t.endStroke();
    t = mk(['A']); t.state.ell[0] = copyOf(E); t._dom.svg.style = {};
    down(t, 7.15, 5);
    ok.push(!t._stroke);
    // switching Handles <-> Gestures mid-session keeps working
    t.setControl('mode', 'gestures'); down(t, 7.15, 5);
    ok.push(t._stroke && t._stroke.kind === 'rotate'); up(t);
    t.setControl('mode', 'handles'); down(t, 7.15, 5);
    ok.push(!t._stroke);
    h = handle(t, 'major'); t._pointerDown({button: 0, pointerId: 1, clientX: h[0], clientY: h[1]});
    ok.push(t._stroke && t._stroke.kind === 'major'); up(t);
    // clicking another group's interior selects it, even inside the active group's ring
    t = mk(['A', 'B']); t.ui.mode = 'gestures'; t._dom.svg.style = {};
    t.state.ell[0] = {mx: 5, my: 5, s1: 1, s2: 1, th: 0};
    t.state.ell[1] = {mx: 7.5, my: 5, s1: 0.5, s2: 0.5, th: 0};
    d0 = t.history._index;
    down(t, 7.2, 5); up(t);
    ok.push(t.ui.active === 1 && t.history._index === d0 && !t._stroke);
    // cursors per zone
    t = gt({}, E); t._dom.plot = {}; t._requestDraw = function () {};
    function cur(x, y, o) {
      var q = px(t, x, y), ev = {clientX: q[0], clientY: q[1]};
      for (var k in (o || {})) ev[k] = o[k];
      t._hover(ev); return t._dom.svg.style.cursor;
    }
    ok.push(cur(5, 5) === 'move' && cur(7.15, 5) === 'grab' && cur(7.6, 5) === 'crosshair' &&
            cur(7.6, 5, {shiftKey: true}) === 'grab' && cur(9.5, 1) === 'default');
    return ok.join(',');
  })()
"))

run_check("Bivariate axes", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [], t, d0, s, c;
    // autofit: dragging a centre to the view edge grows the limits (only grows), one entry
    t = mk(['A']); d0 = t.history._index;
    stroke(t, [[50, 50], [100, 50]]);
    s = t.state;
    ok.push(t.history._index === d0 + 1 && s.xlim[0] <= 0 && s.xlim[1] > 10 && s.ylim.join() === '0,10' &&
            B().contains(s.xlim, s.ylim, s.ell));
    t.undo();
    ok.push(t.state.xlim.join() === '0,10' && near(t.state.ell[0].mx, 5) && t.history._index === d0);
    // a stroke that stays inside leaves the limits alone
    t = mk(['A']); stroke(t, [[50, 50], [55, 50]]);
    ok.push(t.state.xlim.join() === '0,10' && t.state.ylim.join() === '0,10');
    // autofit off: limits stay
    t = mk(['A']); t.setControl('autofit', false); d0 = t.history._index;
    stroke(t, [[50, 50], [100, 50]]);
    ok.push(t.state.xlim.join() === '0,10' && near(t.state.ell[0].mx, 10) && t.history._index === d0 + 1);

    // sidebar limits that hide a group: expand to hold every 2-sigma box + notice, one entry
    t = mk(['A', 'B']); d0 = t.history._index;
    t.receiveControl('xlim', [50, 60]);
    s = t.state;
    ok.push(t.history._index === d0 + 1 && B().contains(s.xlim, s.ylim, s.ell) &&
            s.xlim[1] === 60 && t._flashed && t._flashed.length === 1 &&
            t._flashed[0] === 'Axes expanded to keep every group in view');
    // limits that keep every mean: plain entry, no flash; unchanged is a no-op
    t = mk(['A', 'B']); t.receiveControl('xlim', [-20, 20]);
    ok.push(t.state.xlim.join() === '-20,20' && !t._flashed && t.history._index === 1);
    t.receiveControl('xlim', [-20, 20]);
    ok.push(t.history._index === 1);
    // reset-axes: back to lim0 with no flash when every mean is inside
    t = mk(['A']); t.receiveControl('xlim', [-20, 20]); t.receiveControl('ylim', [-3, 30]);
    t.action('reset-axes');
    ok.push(t.state.xlim.join() === '0,10' && t.state.ylim.join() === '0,10' && !t._flashed);
    // ... and expanded (with the notice) when a mean lies outside lim0
    t = mk(['A']); stroke(t, [[50, 50], [100, 50]]);
    c = centre(t); stroke(t, [[c[0], c[1]], [140, c[1]]]);          // mean now beyond x = 10
    ok.push(t.state.ell[0].mx > 10);
    t.action('reset-axes');
    ok.push(B().contains(t.state.xlim, t.state.ylim, t.state.ell) && t.state.xlim[1] > 10 &&
            t._flashed && t._flashed.length === 1);
    // offset axes: initial layout in the middle of the range
    t = mk(['A'], {xlim: [1000, 1010], ylim: [-5, 5]});
    ok.push(near(t.state.ell[0].mx, 1005) && near(t.state.ell[0].my, 0) &&
            near(t.toSpec().sd_x[0], 1));
    return ok.join(',');
  })()
"))

run_check("Bivariate groups and controls", engine("bivariate"), paste0(bv_script, "
  (function () {
    var ok = [], t, d0, m, c;
    // rename B -> Z keeps the ellipse
    t = mk(['A', 'B']); t.state.ell[1].mx = 8; t.commit(t.state);
    var eB = JSON.stringify(t.state.ell[1]);
    t.receiveControl('groups', 'A, Z');
    ok.push(t.state.groups.join() === 'A,Z' && JSON.stringify(t.state.ell[1]) === eB && !t._flashed);
    // add D: centred, sd = 0.1 m, rho 0; others keep theirs
    t = mk(['A', 'B']); t.state.ell[0].mx = 2; t.commit(t.state);
    var eA = JSON.stringify(t.state.ell[0]);
    t.receiveControl('groups', 'A, B, D');
    m = B().toMarginal(t.state.ell[2]);
    ok.push(t.state.groups.length === 3 && JSON.stringify(t.state.ell[0]) === eA &&
            near(m.mean_x, 5) && near(m.mean_y, 5) && near(m.sd_x, 1) && near(m.sd_y, 1) && near(m.rho, 0));
    // remove A: notice, B keeps its ellipse, one entry, undo brings A back
    t = mk(['A', 'B']); var eB2 = JSON.stringify(t.state.ell[1]); d0 = t.history._index;
    t.receiveControl('groups', 'B');
    ok.push(t.state.groups.join() === 'B' && JSON.stringify(t.state.ell[0]) === eB2 &&
            t._flashed.length === 1 && /A removed/.test(t._flashed[0]) && t.history._index === d0 + 1);
    t.undo(); ok.push(t.state.groups.join() === 'A,B' && t.state.ell.length === 2);
    // Clear restores the initial layout (undoable); no entry when already initial
    t = mk(['A', 'B', 'C']); d0 = t.history._index;
    t.clear(); ok.push(t.history._index === d0);
    c = centre(t); stroke(t, [[c[0], c[1]], [10, 10]]);
    var moved = JSON.stringify(t.state.ell);
    t.clear();
    ok.push(JSON.stringify(t.state.ell) === JSON.stringify(B().initial(['A', 'B', 'C'], t.state.xlim, t.state.ylim)) &&
            t.history._index > d0);
    t.undo(); ok.push(JSON.stringify(t.state.ell) === moved);
    // n and names: one entry each; invalid values (and n x groups > 1e6) are ignored
    t = mk(['A', 'B']); d0 = t.history._index;
    t.receiveControl('n', 500); t.receiveControl('n', 500);
    t.receiveControl('names', {x: ' h ', y: 'w', group: 'g'});
    t.receiveControl('n', 0); t.receiveControl('n', 2.5);
    t.receiveControl('names', {x: 'a', y: 'a', group: 'g'});
    t.receiveControl('xlim', [5, 5]); t.receiveControl('ylim', ['', 3]); t.receiveControl('groups', 'A, A');
    ok.push(t.state.n === 500 && t.state.names.x === 'h' && t.history._index === d0 + 2 &&
            t.state.xlim.join() === '0,10');
    // mode / autofit / active are settings, not history entries
    t.receiveControl('mode', 'gestures'); t.receiveControl('mode', 'bogus');
    t.receiveControl('autofit', false); t.receiveControl('autofit', 'yes');
    t.receiveControl('active', '2'); t.receiveControl('active', '9');
    ok.push(t.ui.mode === 'gestures' && t.ui.autofit === false && t.ui.active === 1 &&
            t.history._index === d0 + 2);
    ok.push(mk(['A'], {mode: 'zzz'}).ui.mode === 'handles' && mk(['A']).ui.autofit === true &&
            mk(['A'], {autofit: false}).ui.autofit === false);
    // I-3: n x groups > 1e6 is refused loudly: no change, one notice, sidebar re-synced
    t = mk(['A', 'B']); d0 = t.history._index;
    var pushed = [];
    t.onControls(function (msgs) { pushed.push(msgs); });
    t.receiveControl('n', 600000);
    ok.push(t.state.n === 200 && t.history._index === d0 && t._flashed && t._flashed.length === 1 &&
            /1e6/.test(t._flashed[0]) && pushed.length === 1 && pushed[0].n.value === 200);
    t.setControl('n', 500000); ok.push(t.state.n === 500000);
    t._flashed = null; pushed = [];
    t.receiveControl('groups', 'A, B, C');
    ok.push(t.state.groups.length === 2 && t._flashed && t._flashed.length === 1 &&
            pushed.length === 1 && pushed[0].groups.value === 'A, B');
    // one group arrives from R as a scalar; names are trimmed
    t = mk(' solo ');
    ok.push(t.state.groups.join() === 'solo' && t.state.ell.length === 1);
    // select-k keys 1-9
    t = mk(['A', 'B', 'C']); t.action('select-3'); t.action('select-9');
    ok.push(t.ui.active === 2);
    return ok.join(',');
  })()
"))

# Bivariate: toSpec() JSON from V8 is accepted by R and matches toMarginal().
bv_json <- function(setup) {
  cx <- engine("bivariate")
  cx$eval(paste0(bv_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify({spec: T.toSpec(), marg: T.state.ell.map(DCR.tools.bivariate.toMarginal)})")
}
bv_cases <- list(
  one_group = "var t = mk(['A']); stroke(t, [[50, 50], [60, 40]]); return t;",
  three_groups = "var t = mk(['A', 'B', 'C']); var h = handle(t, 'major');
    stroke(t, [[h[0], h[1]], [h[0] + 12, h[1] + 3]]); t.action('select-2');
    h = handle(t, 'minor'); stroke(t, [[h[0], h[1]], [h[0] + 6, h[1] - 6]]); return t;",
  offset_axes = "var t = mk(['A', 'B'], {xlim: [1000, 1010], ylim: [-5, 5]});
    var c = centre(t); stroke(t, [[c[0], c[1]], [c[0] + 8, c[1] + 8]]); return t;",
  rho_max = "var t = mk(['A']); t.state.ell[0] = {mx: 5, my: 5, s1: 4, s2: 0.0001, th: 0.4};
    t.commit(t.state); return t;",
  custom_names = "var t = mk(['g1', 'g2']); t.receiveControl('names', {x: 'height', y: 'weight', group: 'sp'});
    t.receiveControl('n', 77); return t;"
)
for (nm in names(bv_cases)) {
  js <- bv_json(bv_cases[[nm]])
  both <- jsonlite::fromJSON(js, simplifyVector = FALSE)
  raw <- jsonlite::fromJSON(jsonlite::toJSON(both$spec, auto_unbox = TRUE, digits = NA))
  marg <- both$marg
  spec <- tryCatch(as_dcr_spec(raw), error = function(e) {
    message("Bivariate round trip failed (", nm, "): ", conditionMessage(e))
    quit(status = 1)
  })
  k <- length(spec$groups)
  stopifnot(inherits(spec, "dcr_spec"), k == length(raw$groups),
            isTRUE(all.equal(spec$mean_x, raw$mean_x, tolerance = 1e-9)),
            isTRUE(all.equal(spec$mean_y, raw$mean_y, tolerance = 1e-9)),
            isTRUE(all.equal(spec$sd_x, raw$sd_x, tolerance = 1e-9)),
            isTRUE(all.equal(spec$sd_y, raw$sd_y, tolerance = 1e-9)),
            isTRUE(all.equal(spec$rho, raw$rho, tolerance = 1e-9)),
            all(spec$sd_x > 0), all(spec$sd_y > 0), all(abs(spec$rho) <= 0.999),
            isTRUE(all.equal(spec$mean_x, vapply(marg, function(m) m$mean_x, 0), tolerance = 1e-9)),
            isTRUE(all.equal(spec$mean_y, vapply(marg, function(m) m$mean_y, 0), tolerance = 1e-9)),
            isTRUE(all.equal(spec$sd_x, vapply(marg, function(m) m$sd_x, 0), tolerance = 1e-9)),
            isTRUE(all.equal(spec$sd_y, vapply(marg, function(m) m$sd_y, 0), tolerance = 1e-9)),
            isTRUE(all.equal(spec$rho, vapply(marg, function(m) m$rho, 0), tolerance = 1e-9)))
  if (nm == "rho_max") stopifnot(abs(spec$rho) == 0.999)
  if (nm == "offset_axes") stopifnot(spec$xlim[1] <= 1000, spec$ylim[2] >= 5)
  if (nm == "custom_names") {
    stopifnot(spec$n == 77, identical(spec$names$x, "height"),
              identical(spec$names$group, "sp"))
  }
  df <- sample_spec(spec, 20)
  stopifnot(nrow(df) == 20L * k, all(is.finite(df[[1]])), all(is.finite(df[[2]])))
  stats <- spec_stats(spec)
  stopifnot(nrow(stats) == k + 1L, all(is.finite(unlist(stats[-1]))))
  df2 <- dcr_sample(spec, seed = 1)
  stopifnot(nrow(df2) == spec$n * k)
}

# Bivariate: Done flushes the sidebar (groups / n / limits / names / mode / autofit).
run_check("Bivariate Done flush", engine(c("bivariate")), paste0(flush_script, "
  (function () {
    var d = new DCR.tools.bivariate(el(), {groups: ['V1', 'V2', 'V3']});
    d._flash = function () {};
    sidebar = {active: '1', groups: 'V1, V2', mode: 'gestures', autofit: false, n: 250,
               xlim: [0, 20], ylim: [-5, 5], names: {x: 'h', y: 'w', group: 'g'}};
    var s = doneSpec(d);
    return [s !== null && s.n === 250 && s.groups.join() === 'V1,V2' && s.xlim[1] === 20 &&
            s.ylim[0] === -5 && s.names.x === 'h' && s.mean_x.length === 2 &&
            d.ui.mode === 'gestures' && d.ui.autofit === false,
            (function () {
              sidebar = {groups: 'A, A', xlim: ['', 3], n: 0, mode: 'x', autofit: 'maybe'};
              var s2 = doneSpec(d);
              return s2 !== null && s2.groups.join() === 'V1,V2' && s2.n === 250;
            })()].join(',');
  })()
"))

# ---- Mosaic ------------------------------------------------------------------
# Pure table maths, drags from the stroke-start snapshot, strokes, categories.
mo_script <- "
  var M = DCR.tools.mosaic;
  var seed = 12345;
  function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
  function mk(opts) {
    var t = new DCR.tools.mosaic({clientWidth: 0, clientHeight: 0,
      getBoundingClientRect: function () { return {left: 0, top: 0}; }}, opts || {});
    t._geo = {x0: 0, y0: 0, w: 200, h: 100};      // 1 px = 1 observation at N = 200
    t._dom = {svg: {setPointerCapture: function () {}}};
    t.render = function () {};
    return t;
  }
  function setCounts(t, m) { var s = t.state; s.counts = m; t.commit(s); }
  function stroke(t, pts) {
    t._pointerDown({button: 0, pointerId: 1, clientX: pts[0][0], clientY: pts[0][1]});
    pts.slice(1).forEach(function (p) {
      t._pointerMove({pointerId: 1, clientX: p[0], clientY: p[1]});
    });
    t._pointerUp({pointerId: 1}); t.endStroke();
  }
  function sum(a) { return a.reduce(function (s, v) { return s + v; }, 0); }
  function flat(m) { return [].concat.apply([], m); }
  function cT(m, c) { return sum(m.map(function (r) { return r[c]; })); }
  function rT(m, r) { return sum(m[r]); }
  function eq(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
  function near(a, b, tol) { return Math.abs(a - b) < tol; }
  function bxOf(t) { return t._borders(t.state.counts, t._geo)[1]; }
"
run_check("Mosaic maths", engine("mosaic"), paste0(mo_script, "
  (function () {
    var ok = [], i, j, k;
    // allocate: exact sums for random weights and totals, ties to the earlier index
    var allExact = true;
    for (i = 0; i < 200; i++) {
      var n = 1 + Math.floor(rnd() * 10), w = [], total = Math.floor(rnd() * 5000);
      for (j = 0; j < n; j++) w.push(rnd() < 0.3 ? 0 : Math.floor(rnd() * 1000));
      var a = M.allocate(total, w);
      if (sum(a) !== total || a.some(function (v) { return v < 0 || v !== Math.round(v); }) ||
          (sum(w) > 0 && a.some(function (v, q) { return w[q] === 0 && v !== 0; }))) allExact = false;
    }
    ok.push(allExact);
    ok.push(eq(M.allocate(1, [1, 1, 1]), [1, 0, 0]) && eq(M.allocate(2, [3, 3, 3]), [1, 1, 0]));
    ok.push(eq(M.allocate(7, [0, 0]), [4, 3]) && eq(M.allocate(2, [0, 0, 0]), [1, 1, 0]));
    ok.push(eq(M.allocate(10, [1, 2, 3]), [2, 3, 5]) && eq(M.allocate(0, [4, 5]), [0, 0]));
    // independent: both margins exactly (3 x 4, N = 997); known 2 x 2
    var m = [[], [], []], left = 997;
    for (i = 0; i < 3; i++) for (j = 0; j < 4; j++) {
      var v = i === 2 && j === 3 ? left : Math.min(left, Math.floor(rnd() * 150));
      m[i].push(v); left -= v;
    }
    var ind = M.independent(m), marg = true;
    for (i = 0; i < 3; i++) if (rT(ind, i) !== rT(m, i)) marg = false;
    for (j = 0; j < 4; j++) if (cT(ind, j) !== cT(m, j)) marg = false;
    ok.push(marg && sum(flat(ind)) === 997 && flat(ind).every(function (v) { return v >= 0; }));
    ok.push(eq(M.independent([[30, 20], [10, 40]]), [[20, 30], [20, 30]]));
    // rescale: sums to N, keeps zeros; the zero table becomes uniform
    var rs = M.rescale([[0, 5, 5], [10, 0, 3]], 41);
    ok.push(sum(flat(rs)) === 41 && rs[0][0] === 0 && rs[1][1] === 0);
    ok.push(eq(M.rescale([[0, 0], [0, 0]], 5), [[2, 1], [1, 1]]));
    // Review focus 3: N below the number of cells; N = 1e6, fast
    ok.push(eq(M.uniform(3, 4, 3), [[1, 1, 1, 0], [0, 0, 0, 0], [0, 0, 0, 0]]));
    var t0 = Date.now(), big = M.rescale(M.uniform(10, 10, 997), 1e6), big2 = M.uniform(10, 10, 1e6);
    var m3 = M.rescale([[1, 2, 3], [4, 5, 6], [7, 8, 9]], 3);
    ok.push(sum(flat(big)) === 1e6 && sum(flat(big2)) === 1e6 && Date.now() - t0 < 1000 &&
            sum(flat(m3)) === 3 && flat(m3).every(function (v) { return v >= 0; }));
    // dragColumn: conserves N; the two totals change by exactly the delta
    var st = [[10, 20, 5], [30, 10, 5]];
    var d = M.dragColumn(st, 0, 15);
    ok.push(cT(d, 0) === 55 && cT(d, 1) === 15 && cT(d, 2) === 10 && sum(flat(d)) === 80 &&
            eq(d.map(function (r) { return r[2]; }), [5, 5]));
    ok.push(cT(M.dragColumn(st, 1, 100), 1) === 40 && cT(M.dragColumn(st, 1, 100), 2) === 0);   // clamp
    ok.push(cT(M.dragColumn(st, 0, -100), 0) === 0 && cT(M.dragColumn(st, 0, -100), 1) === 70);
    ok.push(eq(M.dragColumn(st, 0, 0), st) && eq(M.dragColumn(st, 1, 0), st));
    // each column keeps its row shares (start 10:30 -> 25%/75%)
    ok.push(eq(M.dragColumn([[10, 0], [30, 0]], 0, -20).map(function (r) { return r[0]; }), [5, 15]));
    // zero column revived with an even split (earlier rows first)
    var z = M.dragColumn(st, 0, -100);
    ok.push(eq(M.dragColumn(z, 0, 11).map(function (r) { return r[0]; }), [6, 5]));
    // dragCut: only the column changes, its total is unchanged, clamped at 0
    var c3 = [[10, 20], [30, 10], [10, 10]];
    var dc = M.dragCut(c3, 0, 0, 15);
    ok.push(dc[0][0] === 25 && dc[1][0] === 15 && dc[2][0] === 10 && eq(dc.map(function (r) { return r[1]; }), [20, 10, 10]));
    ok.push(M.dragCut(c3, 0, 0, 100)[0][0] === 40 && M.dragCut(c3, 0, 0, 100)[1][0] === 0 &&
            M.dragCut(c3, 0, 0, -100)[0][0] === 0 && M.dragCut(c3, 0, 0, -100)[1][0] === 40);
    ok.push(eq(M.dragCut(c3, 0, 1, 0), c3));
    // chisq against R chisq.test(correct = FALSE)
    var q = M.chisq([[30, 20], [10, 40]]);
    ok.push(near(q.stat, 16.6666666666667, 1e-6) && q.df === 1 && near(q.p, 4.45570906040561e-05, 1e-6) &&
            near(q.v, 0.408248290463863, 1e-6) && near(q.or, 6, 1e-9) && near(q.rr, 8 / 3, 1e-9) &&
            q.expectedLow === 0);
    q = M.chisq([[12, 7, 4], [5, 15, 8], [9, 3, 20]]);
    ok.push(near(q.stat, 22.7575848064978, 1e-6) && q.df === 4 && near(q.p, 0.000141557058070167, 1e-6) &&
            near(q.v, 0.370261913213462, 1e-6) && q.or === null && q.rr === null);
    q = M.chisq([[5, 5], [0, 5]]);
    ok.push(q.or === null && q.rr === null && M.chisq([[1, 2], [3, 4]]).expectedLow === 4);
    q = M.chisq([[0, 0], [5, 5]]);
    ok.push(q.df === 0 && q.p === null && q.v === null && q.stat === 0);
    q = M.chisq([[1, 3], [2, 4]]);
    ok.push(near(q.stat, 0.0793650793650794, 1e-9));
    return ok.join(',');
  })()
"))

run_check("Mosaic strokes", engine("mosaic"), paste0(mo_script, "
  (function () {
    var ok = [], t, depth, i;
    t = mk({n: 200});                       // 2 x 2 uniform: border at x = 100, cuts at y = 50
    ok.push(eq(t.state.counts, [[50, 50], [50, 50]]) && eq(t.state.cols, ['No', 'Yes']));
    // vertical border: drag right 40 px = 40 observations; one history entry
    depth = t.history._index;
    stroke(t, [[100, 20], [120, 20], [140, 20]]);
    ok.push(eq(t.state.counts, [[70, 30], [70, 30]]) && t.history._index === depth + 1);
    t.undo(); ok.push(eq(t.state.counts, [[50, 50], [50, 50]]));
    // Review focus 1: back to the start inside one stroke = the start table (non-uniform start)
    setCounts(t, [[60, 10], [30, 100]]);
    var start = JSON.parse(JSON.stringify(t.state.counts)); depth = t.history._index;
    var bxp = 90;                                            // border at 90 observations
    stroke(t, [[bxp, 20], [bxp + 40, 20], [bxp + 90, 20], [bxp, 20]]);
    ok.push(eq(t.state.counts, start) && t.history._index === depth);
    stroke(t, [[bxp, 20], [bxp + 500, 20], [bxp - 500, 20], [bxp + 7, 20], [bxp, 20]]);   // clamped both ways
    ok.push(eq(t.state.counts, start) && t.history._index === depth);
    // mid-stroke the table follows the pointer relative to the press
    t._pointerDown({button: 0, pointerId: 1, clientX: bxp, clientY: 20});
    t._pointerMove({pointerId: 1, clientX: bxp + 20, clientY: 20});
    ok.push(cT(t.state.counts, 0) === 110 && cT(t.state.counts, 1) === 90);
    t._pointerMove({pointerId: 1, clientX: bxp - 10, clientY: 20});
    ok.push(cT(t.state.counts, 0) === 80 && cT(t.state.counts, 1) === 120);
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.history._index === depth + 1 && sum(flat(t.state.counts)) === 200);
    t.undo();
    // horizontal cut: drag the column-0 cut (y = 60/90*100 ... uniform here)
    t = mk({n: 200}); depth = t.history._index;
    stroke(t, [[50, 50], [50, 60], [50, 70]]);                   // down 20 px of 100 -> +20
    ok.push(eq(t.state.counts, [[70, 50], [30, 50]]) && t.history._index === depth + 1);
    stroke(t, [[50, 70], [50, 20]]);                              // back up by 50 -> clamped
    ok.push(eq(t.state.counts, [[20, 50], [80, 50]]));
    stroke(t, [[50, 20], [50, 500]]);
    ok.push(t.state.counts[1][0] === 0 && t.state.counts[0][0] === 100 && cT(t.state.counts, 1) === 100);
    // Review focus 2: column dragged to 0 and back out; the zero column's border stays grabbable
    t = mk({n: 200}); setCounts(t, [[50, 50], [30, 70]]);        // col totals 80, 120
    stroke(t, [[80, 20], [0, 20]]);                              // drag border 0 to the left edge
    ok.push(cT(t.state.counts, 0) === 0 && cT(t.state.counts, 1) === 200);
    stroke(t, [[1, 20], [31, 20]]);                              // grab the zero-width border, pull out
    ok.push(cT(t.state.counts, 0) === 30 && eq(t.state.counts.map(function (r) { return r[0]; }), [15, 15]));
    // coincident borders (right edge): left picks the first, right the last
    t = mk({cols: ['a', 'b', 'c'], n: 200}); setCounts(t, [[100, 0, 0], [100, 0, 0]]);
    stroke(t, [[199, 20], [169, 20]]);
    ok.push(eq(t.state.counts.map(function (r) { return r.join(); }), ['85,15,0', '85,15,0']));
    setCounts(t, [[100, 0, 0], [100, 0, 0]]);
    stroke(t, [[199, 20], [199 + 30, 20]]);
    ok.push(eq(t.state.counts, [[100, 0, 0], [100, 0, 0]]));    // right: nothing to take from col c
    // coincident cuts: up picks the first cut, down the last
    t = mk({rows: ['a', 'b', 'c'], n: 150});
    setCounts(t, [[50, 50], [0, 50], [0, 50]]);                 // col 0: two cuts at its bottom
    depth = t.history._index;
    stroke(t, [[30, 99], [30, 79]]);
    ok.push(t.state.counts.map(function (r) { return r[0]; }).join() === '40,10,0' && t.history._index === depth + 1);
    setCounts(t, [[50, 50], [0, 50], [0, 50]]); depth = t.history._index;
    stroke(t, [[30, 99], [30, 150]]);
    ok.push(t.history._index === depth && t.state.counts[2][0] === 0);
    // a zero-width column has no cuts: only its border is hit
    t = mk({n: 200}); setCounts(t, [[0, 100], [0, 100]]);
    var hz = t._hitTest(0, 50), hc = t._hitTest(40, 50);
    ok.push(hz.kind === 'v' && hc.kind === 'h' && hc.list[0].col === 1);
    // Review focus 4: 200 presses without moving (and < 3 px) never add history
    t = mk({n: 200}); depth = t.history._index;
    for (i = 0; i < 200; i++) {
      var pts = [[100, 20], [50, 50], [150, 50], [100, 100], [3, 50]][i % 5];
      t._pointerDown({button: 0, pointerId: 1, clientX: pts[0], clientY: pts[1]});
      if (i % 2) t._pointerMove({pointerId: 1, clientX: pts[0] + 1, clientY: pts[1] + 2});
      t._pointerUp({pointerId: 1}); t.endStroke();
    }
    ok.push(t.history._index === depth && !t._busy && !t._stroke && eq(t.state.counts, [[50, 50], [50, 50]]));
    // a press that wanders out past the dead zone and back is also no change
    stroke(t, [[100, 20], [100, 40], [100, 20]]);
    ok.push(t.history._index === depth);
    // 3 px is a real drag (3 observations); undo restores
    stroke(t, [[100, 20], [103, 20]]);
    ok.push(t.history._index === depth + 1 && cT(t.state.counts, 0) === 103);
    t.undo(); ok.push(eq(t.state.counts, [[50, 50], [50, 50]]));
    // a press off any border does nothing and takes no stroke
    t._pointerDown({button: 0, pointerId: 1, clientX: 20, clientY: 20});
    ok.push(!t._stroke && !t._busy);
    t._pointerDown({button: 2, pointerId: 1, clientX: 100, clientY: 20});
    ok.push(!t._stroke);
    // stale stroke (no end event): the next press finishes it first
    t = mk({n: 200}); depth = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: 100, clientY: 20});
    t._pointerMove({pointerId: 1, clientX: 130, clientY: 20});
    ok.push(t._busy === true);
    stroke(t, [[50, 50], [50, 80]]);
    ok.push(!t._busy && !t._stroke && t.history._index === depth + 2 && sum(flat(t.state.counts)) === 200);
    t._pointerDown({button: 0, pointerId: 7, clientX: bxOf(t), clientY: 20});
    t._pointerDown({button: 0, pointerId: 8, clientX: bxOf(t), clientY: 20});
    ok.push(t._stroke && t._stroke.id === 8);
    t._pointerUp({pointerId: 8}); t.endStroke();
    t._dom.svg.hasPointerCapture = function () { return true; };
    t._pointerDown({button: 0, pointerId: 1, clientX: bxOf(t), clientY: 20});
    t._pointerDown({button: 0, pointerId: 2, clientX: bxOf(t), clientY: 20});
    ok.push(t._stroke.id === 1);
    t._pointerUp({pointerId: 1}); t.endStroke();
    t._dom.svg.hasPointerCapture = undefined;
    // a throwing commit never leaves the engine busy
    t = mk({n: 200}); t.setControl('n', 300);
    var real = t.commit;
    t.commit = function () { throw new Error('boom'); };
    t._pointerDown({button: 0, pointerId: 1, clientX: 100, clientY: 20});
    t._pointerMove({pointerId: 1, clientX: 130, clientY: 20});
    var threw = false;
    try { t._pointerUp({pointerId: 1}); } catch (e) { threw = true; }
    t.commit = real;
    ok.push(threw && !t._busy && !t._stroke);
    // controls and undo during a stroke are queued
    t = mk({n: 200}); depth = t.history._index;
    t._pointerDown({button: 0, pointerId: 1, clientX: 100, clientY: 20});
    t.receiveControl('n', 300);
    ok.push(t.history._index === depth);
    t._pointerMove({pointerId: 1, clientX: 130, clientY: 20});
    t._pointerUp({pointerId: 1}); t.endStroke();
    ok.push(t.history._index === depth + 2 && sum(flat(t.state.counts)) === 300);
    return ok.join(',');
  })()
"))

run_check("Mosaic controls", engine("mosaic"), paste0(mo_script, "
  (function () {
    var ok = [], t, depth, flashed;
    function msgs(t) { flashed = []; t._flash = function (m) { flashed.push(m); }; }
    // defaults and options
    t = mk(); ok.push(eq(t.state.rows, ['Healthy', 'Sick']) && t.state.names.col === 'exposure' &&
                      sum(flat(t.state.counts)) === 200);
    t = mk({cols: 'a', rows: ['x'], n: 0}); ok.push(eq(t.state.cols, ['No', 'Yes']) && sum(flat(t.state.counts)) === 200);
    t = mk({cols: ['a', 'b', 'c'], rows: ['x', 'y'], n: 7, names: {col: 'g', row: 'h'}});
    ok.push(eq(t.toSpec(), {tool: 'mosaic', cols: ['a', 'b', 'c'], rows: ['x', 'y'],
                            names: {col: 'g', row: 'h'}, counts: [[2, 1, 1], [1, 1, 1]]}));
    // N: rescale in one entry; unchanged and invalid add nothing
    t = mk({n: 200}); depth = t.history._index;
    t.setControl('n', 200); t.setControl('n', 0); t.setControl('n', 2.5); t.setControl('n', 2e6);
    t.setControl('n', ''); t.setControl('n', null);
    ok.push(t.history._index === depth);
    t.setControl('n', 3);
    ok.push(sum(flat(t.state.counts)) === 3 && t.history._index === depth + 1);
    t.setControl('n', 1e6);
    ok.push(sum(flat(t.state.counts)) === 1e6 && t.controls().n.value === 1e6);
    t.undo(); t.undo(); ok.push(sum(flat(t.state.counts)) === 200);
    // names
    t.setControl('names', {col: 'a', row: 'a'}); t.setControl('names', {col: 'a', row: ''});
    ok.push(t.state.names.col === 'exposure');
    t.setControl('names', {col: ' k ', row: 'm'});
    ok.push(t.state.names.col === 'k' && t.state.names.row === 'm' && t.history._index === depth + 1);
    // Independent / Uniform / Clear
    t = mk({n: 200}); setCounts(t, [[60, 10], [30, 100]]); depth = t.history._index;
    t.action('independent');
    var ind = t.state.counts;
    ok.push(eq(ind, DCR.tools.mosaic.independent([[60, 10], [30, 100]])) && t.history._index === depth + 1);
    t.action('independent'); ok.push(t.history._index === depth + 1);       // already independent
    t.action('uniform'); ok.push(eq(t.state.counts, [[50, 50], [50, 50]]) && t.history._index === depth + 2);
    t.action('uniform'); ok.push(t.history._index === depth + 2);
    setCounts(t, [[60, 10], [30, 100]]); t.setControl('cols', 'p, q, r');
    t.run('clear');
    ok.push(sum(flat(t.state.counts)) === 200 && t.state.cols.length === 3 && t.state.counts[0].length === 3);
    // Review focus 5: rename keeps counts; add starts at 0; remove deletes, N shrinks, notice, undo
    t = mk({cols: ['a', 'b', 'c'], rows: ['x', 'y', 'z'], n: 90}); msgs(t);
    setCounts(t, [[1, 2, 3], [4, 5, 6], [7, 8, 9]]); depth = t.history._index;
    t.setControl('cols', 'a, B, c');
    ok.push(eq(t.state.counts, [[1, 2, 3], [4, 5, 6], [7, 8, 9]]) && flashed.length === 0);
    t.setControl('rows', 'z, x, y');                                    // reordered: counts follow names
    ok.push(eq(t.state.counts, [[7, 8, 9], [1, 2, 3], [4, 5, 6]]));
    t.setControl('rows', 'z, x, y, w');
    ok.push(eq(t.state.counts[3], [0, 0, 0]) && flashed.length === 0);
    t.setControl('rows', 'z, y, w');                                    // x removed (6 observations)
    ok.push(eq(t.state.counts, [[7, 8, 9], [4, 5, 6], [0, 0, 0]]) && sum(flat(t.state.counts)) === 39 &&
            flashed.length === 1 && flashed[0] === '6 observations of x removed ' + String.fromCharCode(8212) + ' Ctrl+Z to undo');
    t.undo(); ok.push(eq(t.state.counts, [[7, 8, 9], [1, 2, 3], [4, 5, 6], [0, 0, 0]]) && t.state.rows.join() === 'z,x,y,w');
    t.setControl('cols', 'a, c');                                       // B removed (2+5+8 = 15)
    ok.push(t.state.cols.join() === 'a,c' && flashed.length === 2 && /^15 observations of B removed/.test(flashed[1]) &&
            sum(flat(t.state.counts)) === 45 - 15);
    t.undo(); ok.push(sum(flat(t.state.counts)) === 45 && t.state.cols.join() === 'a,B,c');
    t.setControl('cols', 'a'); t.setControl('rows', 'x, x'); t.setControl('rows', 'x');   // invalid: ignored
    ok.push(t.state.cols.length === 3 && t.state.rows.length === 4);
    // removing every populated category leaves a uniform table of the old N
    t = mk({cols: ['a', 'b'], rows: ['x', 'y'], n: 10}); msgs(t);
    setCounts(t, [[4, 0], [6, 0]]);
    t.setControl('cols', 'p, q, r');                                    // a, b -> not a rename
    ok.push(sum(flat(t.state.counts)) === 10 && t.state.counts[0].length === 3);
    return ok.join(',');
  })()
"))

# Mosaic: toSpec() JSON from V8 is accepted by R; sampling gives back the table.
mo_json <- function(setup) {
  cx <- engine("mosaic")
  cx$eval(paste0(mo_script, "var T = (function () {", setup, "})();"))
  cx$eval("JSON.stringify(T.toSpec())")
}
mo_cases <- list(
  two_by_two = "return mk();",
  drag = "var t = mk(); stroke(t, [[100, 20], [160, 20]]); return t;",
  three_by_four_zeros = "var t = mk({cols: ['a', 'b', 'c', 'd'], rows: ['x', 'y', 'z'], n: 120});
    stroke(t, [[50, 20], [0, 20]]); return t;",
  custom_names = "return mk({names: {col: 'group', row: 'status'}, n: 37, rows: ['u', 'v', 'w']});",
  small_n = "return mk({cols: ['a', 'b', 'c'], rows: ['x', 'y', 'z'], n: 4});",
  big_n = "return mk({cols: ['a', 'b', 'c'], rows: ['x', 'y'], n: 1e6});",
  after_categories = "var t = mk({cols: ['a', 'b', 'c'], n: 60}); t._flash = function () {};
    t.setControl('cols', 'a, z, c'); t.setControl('rows', 'Sick, Healthy, Other'); return t;"
)
for (nm in names(mo_cases)) {
  spec <- tryCatch(as_dcr_spec(jsonlite::fromJSON(mo_json(mo_cases[[nm]]))),
                   error = function(e) {
                     message("Mosaic round trip failed (", nm, "): ", conditionMessage(e))
                     quit(status = 1)
                   })
  df <- sample_spec(spec, NULL)
  tab <- table(df[[1]], df[[2]])
  stopifnot(inherits(spec, "dcr_spec"), is.matrix(spec$counts),
            nrow(df) == sum(spec$counts), sum(spec$counts) >= 1,
            identical(names(df), c(spec$names$col, spec$names$row)),
            identical(unname(unclass(tab)), unname(t(spec$counts))),
            identical(levels(df[[1]]), spec$cols), identical(levels(df[[2]]), spec$rows))
  if (nm == "custom_names") stopifnot(identical(names(df), c("group", "status")))
  if (nm == "three_by_four_zeros") stopifnot(any(spec$counts == 0))
}

# Mosaic: Done flushes the sidebar (cols / rows / n / names).
run_check("Mosaic Done flush", engine("mosaic"), paste0(flush_script, "
  (function () {
    var d = new DCR.tools.mosaic(el(), {});
    d._flash = function () {};
    sidebar = {cols: 'a, b, c', rows: 'x, y', n: 300, names: {col: 'g', row: 'h'}};
    var s = doneSpec(d);
    var tot = s.counts.reduce(function (a, r) { return a + r.reduce(function (b, v) { return b + v; }, 0); }, 0);
    return [s !== null && s.cols.join() === 'a,b,c' && s.rows.join() === 'x,y' && tot === 300 &&
            s.names.col === 'g' && s.counts[0].length === 3,
            (function () {
              sidebar = {cols: 'A, A', rows: 'x', n: 0, names: {col: 'a', row: 'a'}};
              var s2 = doneSpec(d);
              return s2 !== null && s2.cols.join() === 'a,b,c' && s2.counts.length === 2;
            })()].join(',');
  })()
"))

cat("JS OK (", length(files), " files checked,History, EchoGuard (+expiry), Tool queue, ",
    "Scatter (+offset range, R round trip), Boxplot (+ordering, R round trip), ",
    "Histogram (+R round trip), Count (+R round trip), Density (+R round trip, Done flush), Bivariate (+R round trip, Done flush), Mosaic (+R round trip, Done flush), ",
    "Done flush, Removal notices OK)\n",
    sep = "")
