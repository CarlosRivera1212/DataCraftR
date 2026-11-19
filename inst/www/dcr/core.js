/* DataCraftR engine core: window.DCR namespace (no other globals).
 * DOM-free pieces (History, palette) also run in V8 for tools/check-js.R. */
(function (root) {
  "use strict";

  var DCR = root.DCR || {};
  root.DCR = DCR;

  // Shared Tableau 10 palette (same as R dcr_palette()).
  DCR.palette = ["#4E79A7", "#F28E2B", "#E15759", "#76B7B2", "#59A14F",
                 "#EDC948", "#B07AA1", "#FF9DA7", "#9C755F", "#BAB0AC"];

  function deepCopy(x) {
    if (typeof structuredClone === "function") return structuredClone(x);
    return JSON.parse(JSON.stringify(x));
  }
  DCR.deepCopy = deepCopy;

  // R sends length-1 vectors as scalars (jsonlite auto_unbox): accept both.
  DCR.asArray = function (x) {
    if (x === null || x === undefined) return [];
    return Array.isArray(x) ? x : [x];
  };

  // ---- Undo/redo history of plain-JSON states ------------------------------
  // At most HISTORY_CAP states; with opts.sizeOf(state) (e.g. number of
  // points) the oldest states are also dropped while the total size exceeds
  // opts.budget. The current state is never dropped.
  var HISTORY_CAP = 200;

  function History(initialState, opts) {
    opts = opts || {};
    this._sizeOf = opts.sizeOf || function () { return 0; };
    this._budget = opts.budget === undefined ? Infinity : opts.budget;
    this._stack = [deepCopy(initialState)];
    this._sizes = [this._sizeOf(initialState)];
    this._index = 0;
  }
  Object.defineProperties(History.prototype, {
    state: { get: function () { return deepCopy(this._stack[this._index]); } },
    canUndo: { get: function () { return this._index > 0; } },
    canRedo: { get: function () { return this._index < this._stack.length - 1; } }
  });
  History.prototype.push = function (state) {
    this._stack.length = this._index + 1;        // drop the redo branch
    this._sizes.length = this._index + 1;
    this._stack.push(deepCopy(state));
    this._sizes.push(this._sizeOf(state));
    var total = this._sizes.reduce(function (a, b) { return a + b; }, 0);
    while (this._stack.length > 1 &&
           (this._stack.length > HISTORY_CAP || total > this._budget)) {
      this._stack.shift();
      total -= this._sizes.shift();
    }
    this._index = this._stack.length - 1;
    return this.state;
  };
  Object.defineProperty(History.prototype, "length", {
    get: function () { return this._stack.length; }
  });
  History.prototype.undo = function () {
    if (this.canUndo) this._index -= 1;
    return this.state;
  };
  History.prototype.redo = function () {
    if (this.canRedo) this._index += 1;
    return this.state;
  };
  DCR.History = History;

  // ---- Echo guard for tool -> sidebar pushes -------------------------------
  // A value pushed to a sidebar input comes back through R as if the user had
  // set it. Values (already normalised by the tool) are recorded per key; an
  // incoming value equal to a pending one is an echo: it and the older
  // pending values (echoes arrive in order) are dropped. Any other value is
  // real input and clears that key's pending list.
  // Pending values expire after opts.ttl ms (default 2000): Shiny never
  // resends a value equal to the last one it sent, so some pushes have no
  // echo and must not linger to swallow a later identical user value.
  // opts.now() is the clock (injectable for tests).
  function EchoGuard(opts) {
    opts = opts || {};
    this._ttl = opts.ttl === undefined ? 2000 : opts.ttl;
    this._now = opts.now || function () { return Date.now(); };
    this._pending = {};
  }
  EchoGuard.prototype.pushed = function (key, value) {
    (this._pending[key] = this._pending[key] || [])
      .push({ v: JSON.stringify(value), t: this._now() });
  };
  EchoGuard.prototype.isEcho = function (key, value) {
    var cutoff = this._now() - this._ttl, json = JSON.stringify(value);
    var list = (this._pending[key] || []).filter(function (e) { return e.t >= cutoff; });
    var i = -1;
    for (var j = 0; j < list.length; j++) if (list[j].v === json) { i = j; break; }
    if (i < 0) {
      delete this._pending[key];
      return false;
    }
    this._pending[key] = list.slice(i + 1);
    return true;
  };
  DCR.EchoGuard = EchoGuard;

  // ---- Tool registry -------------------------------------------------------
  DCR.tools = DCR.tools || {};
  DCR.register = function (name, Class) {
    DCR.tools[name] = Class;
    return Class;
  };

  // ---- Tool base class -----------------------------------------------------
  // Subclasses implement initialState(options), render(), toSpec() (plain
  // object incl. `tool`), setControl(key, value) (ignore unchanged values),
  // and optionally init(options) (non-undoable settings such as this.ui,
  // set before the first state), action(name), and controls() (update
  // messages {key: {value: ...}} for the sidebar inputs ctl_<key>, pushed by
  // syncControls() so keyboard actions and undo keep the sidebar in step),
  // controlValue(key, value) (the value setControl() would apply, normalised,
  // or null; used to recognise echoes of pushed values), stateSize(state) and
  // historyBudget (history size budget, see History).
  // Drawing state lives in this.state (undoable), never in the DOM.
  // Pointer strokes: beginStroke() ... endStroke(); in between, control
  // messages, undo/redo and toolbar actions are queued and applied after the
  // stroke (which the tool commits before calling endStroke()).
  function Tool(el, options) {
    this.el = el;
    this.options = options || {};
    this._listeners = [];
    this._controlListeners = [];
    this._echo = new EchoGuard();
    this._busy = false;
    this._queue = [];
    this.init(this.options);
    var self = this;
    this.history = new History(this.initialState(this.options), {
      sizeOf: function (s) { return self.stateSize(s); },
      budget: this.historyBudget
    });
    this.state = this.history.state;
    if (typeof ResizeObserver === "function") {
      this._resizeObserver = new ResizeObserver(function () { self.render(); });
      this._resizeObserver.observe(el);
    }
    DCR.current = this;
  }
  Tool.prototype.init = function () {};
  Tool.prototype.initialState = function () { return {}; };
  Tool.prototype.render = function () {};
  Tool.prototype.toSpec = function () { throw new Error("toSpec() not implemented"); };
  Tool.prototype.setControl = function () {};
  Tool.prototype.action = function () {};
  Tool.prototype.controls = function () { return {}; };
  Tool.prototype.controlValue = function (key, value) { return value; };
  Tool.prototype.stateSize = function () { return 0; };
  Tool.prototype.historyBudget = Infinity;

  // Strokes: queue what would split or contaminate the stroke's history entry.
  Tool.prototype.beginStroke = function () { this._busy = true; };
  Tool.prototype.endStroke = function () {
    this._busy = false;
    var q = this._queue;
    this._queue = [];
    for (var i = 0; i < q.length && !this._busy; i++) q[i]();
    if (i < q.length) this._queue = q.slice(i).concat(this._queue);
  };
  Tool.prototype._later = function (fn) {
    if (!this._busy) return false;
    this._queue.push(fn);
    return true;
  };

  // Sidebar -> tool (from R). Echoes of our own pushes are dropped.
  Tool.prototype.markPushed = function (key, value) {
    this._echo.pushed(key, this.controlValue(key, value));
  };
  Tool.prototype.receiveControl = function (key, value) {
    if (this._echo.isEcho(key, this.controlValue(key, value))) return;
    var self = this;
    if (this._later(function () { self.setControl(key, value); })) return;
    this.setControl(key, value);
  };

  // Sidebar values read straight from the inputs ({key: value}), applied
  // without the round trip through R: used by Done, because the last edit of
  // a field (committed on blur / change) has not reached the tool yet when
  // the Done click is handled. Invalid values are skipped (controlValue()
  // gives null; R still reports them on its own path) and unchanged ones are
  // no-ops in setControl(); an error never stops Done.
  Tool.prototype.flushControls = function (values) {
    var self = this;
    Object.keys(values || {}).forEach(function (key) {
      try {
        if (self.controlValue(key, values[key]) !== null) self.setControl(key, values[key]);
      } catch (e) { /* ignored: Done must still send the spec */ }
    });
  };

  Tool.prototype.onChange = function (cb) { this._listeners.push(cb); };
  Tool.prototype.notify = function () {
    for (var i = 0; i < this._listeners.length; i++) this._listeners[i](this);
  };
  Tool.prototype.onControls = function (cb) { this._controlListeners.push(cb); };
  Tool.prototype.syncControls = function () {
    if (!this._controlListeners.length) return;
    var msgs = this.controls();
    for (var i = 0; i < this._controlListeners.length; i++) this._controlListeners[i](msgs);
  };
  Tool.prototype._show = function (state) {
    this.state = state;
    this.render();
    this.notify();
    this.syncControls();
  };
  Tool.prototype.commit = function (state) {
    this._show(this.history.push(state));
  };
  Tool.prototype.undo = function () {
    if (this._later(this.undo.bind(this))) return;
    if (this.history.canUndo) this._show(this.history.undo());
  };
  Tool.prototype.redo = function () {
    if (this._later(this.redo.bind(this))) return;
    if (this.history.canRedo) this._show(this.history.redo());
  };
  // Clear = back to the initial state for the current options, undoable.
  Tool.prototype.clear = function () {
    this.commit(this.initialState(this.options));
  };
  Tool.prototype.run = function (name) {
    if (this._later(this.run.bind(this, name))) return;
    if (name === "undo" || name === "redo" || name === "clear") this[name]();
    else this.action(name);
  };
  Tool.prototype.destroy = function () {
    if (this._resizeObserver) this._resizeObserver.disconnect();
    if (DCR.current === this) DCR.current = null;
  };
  DCR.Tool = Tool;

  // Subclass helper: DCR.extend(Base, {initialState: ..., render: ...}).
  DCR.extend = function (Base, proto) {
    function Sub(el, options) { Base.call(this, el, options); }
    Sub.prototype = Object.create(Base.prototype);
    Sub.prototype.constructor = Sub;
    for (var k in proto) {
      if (Object.prototype.hasOwnProperty.call(proto, k)) Sub.prototype[k] = proto[k];
    }
    return Sub;
  };

  // ---- Done: send the latest spec as an event (no debounce race) -----------
  // DCR.flushSidebar(tool) (shiny-binding.js) first applies the sidebar's
  // current values, so an edit made right before clicking Done is kept.
  DCR.done = function (tool) {
    tool = tool || DCR.current;
    if (!tool || !root.Shiny) return;
    if (DCR.flushSidebar) {
      try { DCR.flushSidebar(tool); } catch (e) { /* send what we have */ }
    }
    root.Shiny.setInputValue("tool_done:dcr.spec", JSON.stringify(tool.toSpec()),
                             { priority: "event" });
  };

  // ---- Delegated listeners (browser only) ----------------------------------
  if (typeof document === "undefined") return;

  document.addEventListener("click", function (ev) {
    var btn = ev.target.closest ? ev.target.closest("[data-dcr-action]") : null;
    if (!btn || !DCR.current) return;
    ev.preventDefault();
    var name = btn.getAttribute("data-dcr-action");
    if (name === "done") DCR.done();
    else DCR.current.run(name);
  });

  function isTyping(el) {
    if (!el) return false;
    var tag = el.tagName;
    return el.isContentEditable || tag === "INPUT" || tag === "TEXTAREA" ||
      tag === "SELECT";
  }

  document.addEventListener("keydown", function (ev) {
    var tool = DCR.current;
    if (ev.key === "Escape") {
      // Esc in a field or one already handled (dropdown, edit) is not Cancel.
      if (isTyping(ev.target) || ev.defaultPrevented) return;
      var cancel = document.getElementById("cancel");
      if (cancel) { ev.preventDefault(); cancel.click(); }
      return;
    }
    if (!tool) return;
    var mod = ev.ctrlKey || ev.metaKey;
    var key = (ev.key || "").toLowerCase();
    if (mod && key === "z") {
      if (isTyping(ev.target)) return;           // keep native text undo
      ev.preventDefault();
      if (ev.shiftKey) tool.redo(); else tool.undo();
      return;
    }
    if (mod || ev.altKey || isTyping(ev.target)) return;
    if (/^[1-9]$/.test(ev.key)) {
      ev.preventDefault();
      tool.action("select-" + ev.key);
    } else if (ev.key === "[") {
      ev.preventDefault();
      tool.action("brush-down");
    } else if (ev.key === "]") {
      ev.preventDefault();
      tool.action("brush-up");
    }
  });
})(typeof window !== "undefined" ? window : this);
