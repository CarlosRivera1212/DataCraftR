console.log("Hello Boxplot JS!!!");

let par = {
  dis: "n",
  x: [],
  cat: [],
  nv: 4,
  step: 160,
  w: 128,
  ymn: 0,
  ymx: 1,
  cl: [],
  cb: [],
  wfac: 1.5,
};

const xSize = 700;
const ySize = 700;
const margin = 30;
const xMax = xSize - margin * 2;
const yMax = ySize - margin * 2;

let box_list = [];

for (let i = 0; i < par.nv; i++) {
  par.x.push(par.step / 2 + i * par.step);
  par.cat.push("V" + (i + 1));
}

//   //   //   //   //   //   //   //   //
// SHINY EVENTS

Shiny.addCustomMessageHandler("update_params", (new_params) => {
  par.nv = new_params.nv;
  // par.dis = new_params.dis;
  let cat = new_params.cat;
  par.cat = typeof cat === "object" ? cat : [cat];
  par.cl = new_params.coll;
  par.cb = new_params.colb;

  par.step = xMax / par.nv;
  par.w = par.step * 0.8;

  par.x = [];
  for (let i = 0; i < par.nv; i++) {
    par.x.push(par.step / 2 + i * par.step);
  }

  box_init();

  x.domain(par.cat);
  x_axis.transition().duration(500).call(d3.axisBottom(x));
});

Shiny.addCustomMessageHandler("update_y_scale", (new_params) => {
  par.ymn = new_params.iymn;
  par.ymx = new_params.iymx;

  update_ax("init");
});

Shiny.addCustomMessageHandler("dist_click", (new_params) => {
  par.dis = new_params.dis;
  par.wfac = par.dis == "n" ? 1.5 : 0.5;
  update_ax("dist");
});

Shiny.addCustomMessageHandler("realign_click", (msg) => {
  update_ax("align");
});

Shiny.addCustomMessageHandler("rest_click", (msg) => {
  box_init();
});

Shiny.addCustomMessageHandler("data_click", (msg) => {
  if (box_list.length > 0) {
    let q1_tot = [];
    let q2_tot = [];
    let q3_tot = [];

    for (let i = 0; i < box_list.length; i++) {
      let bi = box_list[i].select(".box");
      q1_tot.push(parseFloat(bi.attr("q1")));
      q2_tot.push(parseFloat(bi.attr("q2")));
      q3_tot.push(parseFloat(bi.attr("q3")));
    }
    let data = {
      rand_gen: Math.random(),
        q1: q1_tot,
        q2: q2_tot,
        q3: q3_tot
    };
    // Shiny.setInputValue("data_js", null);
    Shiny.setInputValue("data_js", data);
    console.log("DATA RETURN");
  }
});

//   //   //   //   //   //   //   //   //
// INIT PLOT

const svg = d3
  .select("#b_pp_id")
  .append("svg")
  .attr("width", xSize)
  .attr("height", ySize)
  .append("g")
  .attr("transform", "translate(" + 1.9 * margin + "," + margin + ")");

const svg_bg = svg.append("g").attr("class", "bg");
const svg_rec = svg.append("g").attr("class", "rec");
const svg_hov = svg.append("g").attr("class", "hov");

const x = d3.scaleBand().domain(par.cat).range([0, xMax]);
const y = d3.scaleLinear().domain([0, 1]).range([yMax, 0]);

const x_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0," + yMax + ")")
  .call(d3.axisBottom(x));

const y_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0,0)")
  .call(d3.axisLeft(y));

const rec_clk = svg_rec
  .append("rect")
  .attr("width", xMax)
  .attr("height", yMax)
  .attr("fill", "#0078f01E")
  // .attr("opacity", 0.05)
  .style("pointer-events", "none");

const hl_hov = svg_hov
  .append("line")
  .attr("x1", x(0))
  .attr("fill", "none")
  .attr("stroke", "#666666")
  .attr("stroke-width", 1)
  .style("pointer-events", "none")
  .style("opacity", 0.1);

//   //   //   //   //   //   //   //   //
// MOUSE

// function drag() {
//   return d3.drag().on("drag", (e, d) => {
//     update_box(d.i, d.t, e.y);
//   });
// }
// box_list[0].select(".q1").datum({i:0, t:'.q1'}).call(drag());

const drag = d3
  .drag()
  .on("drag", function (e, d) {
    hl_hov
      .attr("x2", par.x[d.bi] - par.w / 2)
      .attr("y1", e.y)
      .attr("y2", e.y)
      .style("opacity", 1);

    const box_i = box_list[d.bi];
    let q1 = parseFloat(box_i.select(".box").attr("q1"));
    let q3 = parseFloat(box_i.select(".box").attr("q3"));
    let ny = 0;

    let ymn = y(par.ymn);
    let ymx = y(par.ymx);

    if (d.t == ".q1") {
      ny = Math.max(ymx, Math.min(ymn, e.y));
      update_box(d.bi, y.invert(ny), q3);
    } else if (d.t == ".q2") {
      let icr2 = (y(q1) - y(q3)) / 2;
      ny = Math.max(ymx, Math.min(ymn, e.y + icr2) - icr2);
      update_box(d.bi, y.invert(ny + icr2), y.invert(ny - icr2));
    } else if (d.t == ".q3") {
      ny = Math.max(ymx, Math.min(ymn, e.y));
      update_box(d.bi, q1, y.invert(ny));
    }
  })
  .on("end", function () {
    hl_hov.style("opacity", 0);
    update_ax();
  });

function box_init() {
  box_list.forEach((c) => c.remove());
  box_list = [];

  for (let i = 0; i < par.nv; i++) {
    box_list.push(create_box(par.x[i], par.cl[i], par.cb[i]));
  }

  for (let i = 0; i < box_list.length; i++) {
    box_list[i].select(".q1").datum({ bi: i, t: ".q1" }).call(drag);
    box_list[i].select(".q2").datum({ bi: i, t: ".q2" }).call(drag);
    box_list[i].select(".q3").datum({ bi: i, t: ".q3" }).call(drag);

    update_box(i, 0.4, 0.6);
  }
  update_ax();
}

box_init();

//   //   //   //   //   //   //   //   //
// FUNCTIONS

function create_box(xc, cl, cb) {
  let w = par.w;
  const x = xc - w / 2;
  const new_box = svg_rec.append("g");

  const box = new_box
    .append("rect")
    .attr("class", "box")
    .attr("x", x)
    .attr("q1", 0.3)
    .attr("q3", 0.6)
    .attr("width", w)
    // .attr("stroke", "#000")
    .attr("fill", cb || "white");

  const w1line = new_box
    .append("line")
    .attr("class", "w1")
    .attr("x1", (2 * x + w) / 2)
    .attr("x2", (2 * x + w) / 2)
    .attr("stroke", "#999")
    .attr("stroke-width", 3);

  const w2line = new_box
    .append("line")
    .attr("class", "w2")
    .attr("x1", (2 * x + w) / 2)
    .attr("x2", (2 * x + w) / 2)
    .attr("stroke", "#999")
    .attr("stroke-width", 3);

  const q1line = new_box
    .append("line")
    .attr("class", "q1")
    .attr("x1", x)
    .attr("x2", x + w)
    .attr("stroke", cl)
    .attr("opacity", 0.9)
    .attr("stroke-width", 6)
    .style("cursor", "ns-resize");

  const q2line = new_box
    .append("line")
    .attr("class", "q2")
    .attr("x1", x)
    .attr("x2", x + w)
    .attr("stroke", cl)
    .attr("opacity", 1.0)
    .attr("stroke-width", 6)
    .style("cursor", "ns-resize");

  const q3line = new_box
    .append("line")
    .attr("class", "q3")
    .attr("x1", x)
    .attr("x2", x + w)
    .attr("stroke", cl)
    .attr("opacity", 0.9)
    .attr("stroke-width", 6)
    .style("cursor", "ns-resize");

  return new_box;
}

function update_box(bi, q1, q3) {
  const box_i = box_list[bi];

  if (q1 === null) q1 = box_i.select(".box").attr("q1");
  if (q3 === null) q3 = box_i.select(".box").attr("q3");

  q1 = parseFloat(q1);
  q3 = parseFloat(q3);
  let q2 = (q1+q3)/2;

  if (q1 > q3) {
    return;
  }

  box_i
    .select(".box")
    // .transition().duration(500)
    .attr("q1", q1)
    .attr("q3", q3)
    .attr("q2", q2)
    .attr("mn", q1 - par.wfac * (q3 - q1))
    .attr("mx", q3 + par.wfac * (q3 - q1))
    .attr("y", y(q3))
    .attr("height", y(q1) - y(q3))
    .transition()
    .duration(500);

  box_i.select(".q1").attr("y1", y(q1)).attr("y2", y(q1));

  box_i.select(".q3").attr("y1", y(q3)).attr("y2", y(q3));

  box_i
    .select(".q2")
    .attr("y1", y(q2))
    .attr("y2", y(q2));

  box_i
    .select(".w1")
    .attr("y1", y(q1) + par.wfac * (y(q1) - y(q3)))
    .attr("y2", y(q1));

  box_i
    .select(".w2")
    .attr("y1", y(q3))
    .attr("y2", y(q3) - par.wfac * (y(q1) - y(q3)));
}

function update_ax(type = "na") {
  if (type == "init") {
    y.domain([par.ymn, par.ymx]);

    for (let i = 0; i < box_list.length; i++) {
      let yq3 = parseFloat(box_list[i].select(".box").attr("y"));
      let hq1 = parseFloat(box_list[i].select(".box").attr("height"));
      update_box(i, y.invert(yq3 + hq1), y.invert(yq3));
    }
  } else {
    if (type == "dist") {
      for (let i = 0; i < box_list.length; i++) {
        update_box(i, null, null);
      }
    }

    let mn_tot = [];
    let mx_tot = [];
    box_list.forEach((bi) => {
      mn_tot.push(bi.select(".box").attr("mn"));
      mx_tot.push(bi.select(".box").attr("mx"));
    });

    par.ymn = Math.min(...mn_tot) - (y.invert(0) - y.invert(20));
    par.ymx = Math.max(...mx_tot) + (y.invert(0) - y.invert(20));

    if (type == "align") {
      for (let i = 0; i < box_list.length; i++) {
        let pm = (par.ymn + par.ymx) / 2;
        let yq3 = parseFloat(box_list[i].select(".box").attr("y"));
        let hq1 = parseFloat(box_list[i].select(".box").attr("height"));
        let r2 = (y.invert(yq3) - y.invert(yq3 + hq1)) / 2;
        update_box(i, pm - r2, pm + r2);
      }
    }

    y.domain([par.ymn, par.ymx]);
  }

  for (let i = 0; i < box_list.length; i++) {
    let pre_q1 = box_list[i].select(".box").attr("q1");
    let pre_q3 = box_list[i].select(".box").attr("q3");
    update_box(i, pre_q1, pre_q3);
  }

  y_axis.transition().duration(500).call(d3.axisLeft(y));
}
