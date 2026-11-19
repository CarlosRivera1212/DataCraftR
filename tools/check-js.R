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
    stroke(t, [[50, 90], [50, 90], [50, 90], [50, 90]]);
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

cat("JS OK (", length(files), " files checked, History, EchoGuard (+expiry), Tool queue, ",
    "Scatter (+offset range, R round trip), Boxplot (+ordering, R round trip), ",
    "Histogram (+R round trip), Count (+R round trip), Density (+R round trip, Done flush), ",
    "Done flush, Removal notices OK)\n",
    sep = "")
