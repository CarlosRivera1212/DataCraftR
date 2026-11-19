/* The only file that knows about Shiny: one input binding for `.dcr-tool`
 * plus the sidebar inputs built by dcr_seg_input() / dcr_fields_input().
 * Tool value = the tool's spec as a JSON string, parsed in R by the
 * "dcr.spec" input handler. Loaded after core.js and the tool scripts. */
(function (root) {
  "use strict";

  var Shiny = root.Shiny, $ = root.jQuery, DCR = root.DCR;
  if (!Shiny || !$ || !DCR) return;

  var instances = new WeakMap();   // element -> tool (no state in the DOM)

  // Tool -> sidebar: push update messages to ctl_<key> through that input's
  // own Shiny binding (same messages as update*Input()). Value-only messages
  // equal to the input's current value are skipped. The input then reports
  // the value back through R; the tool records each pushed value so that
  // echo is dropped (DCR.EchoGuard) instead of being applied as user input.
  function pushControls(tool, msgs) {
    Object.keys(msgs).forEach(function (key) {
      var el = document.getElementById("ctl_" + key);
      var binding = el && $(el).data("shiny-input-binding");
      if (!binding || !binding.receiveMessage) return;
      var msg = msgs[key];
      var changed = "value" in msg &&
        JSON.stringify(binding.getValue(el)) !== JSON.stringify(msg.value);
      var onlyValue = Object.keys(msg).length === 1 && "value" in msg;
      if (onlyValue && !changed) return;
      if (changed) tool.markPushed(key, msg.value);
      binding.receiveMessage(el, msg);
    });
  }

  function toolFor(el) {
    var tool = instances.get(el);
    if (tool) return tool;
    var name = el.getAttribute("data-tool");
    var Class = DCR.tools[name];
    if (!Class) throw new Error("DataCraftR: unknown tool '" + name + "'");
    var opts = JSON.parse(el.getAttribute("data-options") || "{}");
    tool = new Class(el, opts);
    instances.set(el, tool);
    tool.onControls(function (msgs) { pushControls(tool, msgs); });
    tool.render();
    return tool;
  }

  // Done: read every sidebar input ctl_<key> through its own binding and
  // apply the values to the tool (Tool.flushControls), and send the seed
  // field's current value, so edits not yet committed (blur, change,
  // debounce) are part of what Done returns.
  DCR.flushSidebar = function (tool) {
    var values = {};
    $("[id^='ctl_']").each(function () {
      var b = $(this).data("shiny-input-binding");
      if (!b) return;
      try { values[this.id.slice(4)] = b.getValue(this); } catch (e) { /* skip */ }
    });
    tool.flushControls(values);
    var seed = document.getElementById("seed");
    var sb = seed && $(seed).data("shiny-input-binding");
    if (sb) Shiny.setInputValue("seed", sb.getValue(seed));
  };

  var binding = new Shiny.InputBinding();
  $.extend(binding, {
    find: function (scope) { return $(scope).find(".dcr-tool"); },
    initialize: function (el) { toolFor(el); },
    getValue: function (el) { return JSON.stringify(toolFor(el).toSpec()); },
    getType: function () { return "dcr.spec"; },
    subscribe: function (el, callback) {
      toolFor(el).onChange(function () { callback(true); });
    },
    unsubscribe: function () {},
    getRatePolicy: function () { return { policy: "debounce", delay: 250 }; },
    receiveMessage: function (el, msg) {
      var tool = toolFor(el);
      Object.keys(msg).forEach(function (k) { tool.receiveControl(k, msg[k]); });
    }
  });
  Shiny.inputBindings.register(binding, "DataCraftR.tool");

  // ---- Segmented single choice: value = data-value of the pressed button ---
  var segValues = new WeakMap();   // element -> selected value
  var segChoices = new WeakMap();  // element -> JSON of the built choices

  function segButtons(el) {
    return Array.prototype.slice.call(el.querySelectorAll("button[data-value]"));
  }
  function segValue(el) {
    if (segValues.has(el)) return segValues.get(el);
    var on = segButtons(el).filter(function (b) {
      return b.getAttribute("aria-pressed") === "true";
    })[0];
    return on ? on.getAttribute("data-value") : null;
  }
  function segSet(el, value) {
    value = String(value);
    segValues.set(el, value);
    segButtons(el).forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-value") === value ? "true" : "false");
    });
  }
  // choices: [{value, label, color?}], built with textContent (user labels).
  function segBuild(el, choices) {
    var json = JSON.stringify(choices);
    if (segChoices.get(el) === json) return;
    segChoices.set(el, json);
    var value = segValue(el);
    el.textContent = "";
    choices.forEach(function (c) {
      var b = document.createElement("button");
      b.type = "button";
      b.setAttribute("data-value", String(c.value));
      if (c.color) {
        var dot = document.createElement("span");
        dot.className = "dcr-dot";
        dot.style.background = c.color;
        b.appendChild(dot);
      }
      var label = document.createElement("span");
      label.textContent = c.label;
      b.appendChild(label);
      el.appendChild(b);
    });
    if (value !== null) segSet(el, value);
  }

  var seg = new Shiny.InputBinding();
  $.extend(seg, {
    find: function (scope) { return $(scope).find(".dcr-seg-input"); },
    getValue: function (el) { return segValue(el); },
    subscribe: function (el, callback) {
      $(el).on("click.dcrSeg", "button[data-value]", function () {
        segSet(el, this.getAttribute("data-value"));
        callback(false);
      });
      $(el).on("change.dcrSeg", function () { callback(false); });
    },
    unsubscribe: function (el) { $(el).off(".dcrSeg"); },
    receiveMessage: function (el, msg) {
      if (msg.choices) segBuild(el, DCR.asArray(msg.choices));
      if ("value" in msg) segSet(el, msg.value);
      $(el).trigger("change");
    }
  });
  Shiny.inputBindings.register(seg, "DataCraftR.seg");

  // ---- Several fields as one value: array, or object keyed by data-key -----
  function fieldInputs(el) {
    return Array.prototype.slice.call(el.querySelectorAll("input"));
  }
  function fieldValue(input) {
    if (input.type !== "number") return input.value;
    if (/^\s*$/.test(input.value)) return null;
    var v = Number(input.value);
    return isNaN(v) ? null : v;
  }

  var fields = new Shiny.InputBinding();
  $.extend(fields, {
    find: function (scope) { return $(scope).find(".dcr-fields-input"); },
    getValue: function (el) {
      var inputs = fieldInputs(el);
      var keyed = inputs.length > 0 && inputs.every(function (i) { return i.hasAttribute("data-key"); });
      if (!keyed) return inputs.map(fieldValue);
      var out = {};
      inputs.forEach(function (i) { out[i.getAttribute("data-key")] = fieldValue(i); });
      return out;
    },
    subscribe: function (el, callback) {
      $(el).on("change.dcrFields", function () { callback(false); });
    },
    unsubscribe: function (el) { $(el).off(".dcrFields"); },
    receiveMessage: function (el, msg) {
      if (!("value" in msg)) return;
      var v = msg.value;
      fieldInputs(el).forEach(function (input, i) {
        var x = Array.isArray(v) ? v[i] : v[input.getAttribute("data-key")];
        if (x !== undefined) input.value = x === null ? "" : String(x);
      });
      $(el).trigger("change");
    }
  });
  Shiny.inputBindings.register(fields, "DataCraftR.fields");
})(window);
