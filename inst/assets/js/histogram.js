console.log("Hello Histogram JS!!!");

//
//
// arrows-collapse
// arrow-bar-up
// arrow-bar-down
// arrow-left-circle
// arrow-right
// arrow-clockwise
// arrow-reapeat
//
// 123
// alphabet
// download
// file-earmark-arrow-down
// box-arrow-left
//
//

let params = {
  nv: 1,
  v: "V1",
  nb: 10,
  xmn: 0,
  xmx: 10,
  ymx: 100,
  step: 1,
  med: [],
  col: ["#000"],
};

const xSize = 700;
const ySize = 700;
const margin = 30;
const xMax = xSize - margin * 3;
const yMax = ySize - margin * 2;

let hist_list = {};

//   //   //   //   //   //   //   //   //
// SHINY EVENTS

Shiny.addCustomMessageHandler("update_params", (new_params) => {
  params.nv = new_params.nv;
  params.nb = new_params.nb;
  params.col = new_params.col;

  hist_init();
});

Shiny.addCustomMessageHandler("update_axis", (new_params) => {
  params.xmn = new_params.xmn;
  params.xmx = new_params.xmx;
  params.ymx = new_params.ymx;

  update_ax();
});

Shiny.addCustomMessageHandler("select_var", (new_params) => {
  params.v = new_params.v;
});

Shiny.addCustomMessageHandler("reset_click", (msg) => {
  hist_init();
});

Shiny.addCustomMessageHandler("alg_up_click", (msg) => {
  for (let i = 0; i < params.nb; i++) {
    update_bar(i, 0);
  }
});

Shiny.addCustomMessageHandler("alg_dw_click", (msg) => {
  for (let i = 0; i < params.nb; i++) {
    update_bar(i, yMax);
  }
});

Shiny.addCustomMessageHandler("data_click", (msg) => {
  let data = {};
  for (let i in hist_list) {
    const hi = hist_list[i].selectAll(".bar").nodes();
    data[i] = hi.map((d) => Math.round(y.invert(+d.getAttribute("y"))));
  }
  // hist_list[params.v]
  //   .selectAll(".bar")
  //   .nodes()
  //   .map((d) => x.invert(+d.getAttribute("x")));

  console.log("DATA RETURN");
  Shiny.setInputValue("data_js", data);
});

//   //   //   //   //   //   //   //   //
// INIT PLOT

const svg = d3
  .select("#h_pp_id")
  .append("svg")
  .attr("width", xSize)
  .attr("height", ySize)
  .append("g")
  .attr("transform", "translate(" + 2 * margin + "," + margin + ")");

const svg_bg = svg.append("g").attr("class", "bg");
const svg_rec = svg.append("g").attr("class", "rec");
const svg_leg = svg.append("g").attr("class", "leg");
const svg_hov = svg.append("g").attr("class", "hov");

const x = d3.scaleLinear().domain([params.xmn, params.xmx]).range([0, xMax]);
const y = d3.scaleLinear().domain([0, params.ymx]).range([yMax, 0]);

const x_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0," + yMax + ")")
  .call(d3.axisBottom(x));

const y_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0,0)")
  .call(d3.axisLeft(y));

const hl_hov = svg_hov
  .append("line")
  .attr("x1", x(0))
  .attr("stroke", "#666")
  .attr("stroke-width", 1)
  .style("pointer-events", "none");

const rec_clk = svg_hov
  .append("rect")
  .attr("width", xMax)
  .attr("height", yMax)
  .attr("opacity", 0.0)
  .attr("fill", "#0078f01E")
  .style("pointer-events", "all");

// hist_init();

//   //   //   //   //   //   //   //   //
// MOUSE

let dragging = false;
rec_clk
  .on("mousedown", (e) => {
    dragging = true;
  })
  .on("mousemove", (e) => {
    let [nx, ny] = d3.pointer(e);

    hl_hov.attr("x2", nx).attr("y1", ny).attr("y2", ny).style("opacity", 1);

    if (!dragging) return;

    ny = y(Math.round(y.invert(ny)));

    let bi = NaN;
    let dif = xMax;
    for (let i in params.med) {
      let dif_i = Math.abs(params.med[i] - nx);
      if (dif_i < dif) {
        bi = i;
        dif = dif_i;
      }
    }

    update_bar(bi, ny);
  })
  .on("mouseup", () => {
    dragging = false;
  })
  .on("mouseleave", () => {
    dragging = false;
    hl_hov.style("opacity", 0);
  });

//   //   //   //   //   //   //   //   //
// FUNCTIONS

function hist_create(col) {
  let step = params.step;
  let xmx = params.xmx;
  const new_hist = svg_rec.append("g");

  xmn = 0;
  for (let i = 0; xmn < xmx && i < params.nb; i++) {
    const bar = new_hist
      .append("rect")
      .attr("class", "bar")
      .attr("i", i)
      .attr("x", x(xmn))
      .attr("width", x(step))
      .attr("y", y(0))
      .attr("height", 0)
      .attr("fill", col)
      .attr("opacity", 0.3)
      .attr("stroke", "#000");

    xmn += step;
  }

  return new_hist;
}

function hist_init() {
  create_legend();

  params.step = (params.xmx - params.xmn) / params.nb;
  for (let i in hist_list) {
    hist_list[i].remove();
  }

  for (let i = 0; i < params.nv; i++) {
    col = params.col[i];
    hist_list["V" + (i + 1)] = hist_create(col);
  }

  // params.med = [];
  // for (let i = 0; xmn < xmx && i < params.nb; i++) {
  //   params.med.push((xmn + (xmn + step)) / 2);
  //   xmn += step;
  // }

  mstp = xMax / params.nb;
  mxmn = mstp / 2;
  params.med = [];
  for (let i = 0; mxmn < xMax && i < params.nb; i++) {
    params.med.push(mxmn);
    mxmn += mstp;
  }
}

function update_bar(bi, ny) {
  hist_list[params.v]
    .select("[i='" + bi + "']")
    .attr("y", ny)
    .attr("height", yMax - ny);
}

function update_ax() {
  x.domain([params.xmn, params.xmx]);
  x_axis.transition().duration(500).call(d3.axisBottom(x));

  y.domain([0, params.ymx]);
  y_axis.transition().duration(500).call(d3.axisLeft(y));
}

function create_legend() {
  svg_leg.selectAll("circle").remove();
  svg_leg.selectAll('text').remove();

  for (let i = 0; i < params.nv; i++) {
    svg_leg
      .append("circle")
      .attr("cx", xMax-40)
      .attr("cy", (20 * i)+20)
      .attr("r", 6)
      .style("fill", params.col[i]);

    svg_leg
      .append("text")
      .attr("x", xMax-30)
      .attr("y", (20 * i)+20)
      .text('V'+(i+1))
      .style("font-size", "15px")
      .attr("alignment-baseline", "middle");
  }
}
