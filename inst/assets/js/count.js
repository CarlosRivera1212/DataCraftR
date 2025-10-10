console.log("Hello Bar Count JS!!!");

let par = {
  nv: 3,
  v: "V1",
  cat: ["C1", "C2", "C3"],
  ymx: 100,
  col: ["#ff0000", "#00ff00", "#0000ff"],
};

const xSize = 700;
const ySize = 700;
const margin = 30;
const xMax = xSize - margin * 3;
const yMax = ySize - margin * 2;

//   //   //   //   //   //   //   //   //
// SHINY EVENTS

Shiny.addCustomMessageHandler("update_params", (new_par) => {
  par.nv = new_par.nv;
  par.cat = new_par.cat;
  par.col = new_par.col;

  update_ax_x();
  create_bars();
});

Shiny.addCustomMessageHandler("update_y", (new_ymx) => {
  par.ymx = new_ymx;
  update_ax_y();
});

Shiny.addCustomMessageHandler("align", (al) => {
  update_align(al);
});


Shiny.addCustomMessageHandler("data_click", (_) => {
  let count_tot = [];
    
  svg_rec.selectAll(".bar").each(function () {
    let yi = d3.select(this).attr("y");
    let ci = Math.round(y.invert(yi));
    count_tot.push(ci);
  });
  
  Shiny.setInputValue("data_js", count_tot);
  console.log("DATA RETURN");
});

//   //   //   //   //   //   //   //   //
// INIT PLOT

const svg = d3
  .select("#c_pp_id")
  .append("svg")
  .attr("width", xSize)
  .attr("height", ySize)
  .append("g")
  .attr("transform", "translate(" + 2 * margin + "," + margin + ")");

const svg_bg = svg.append("g").attr("class", "bg"); // background
const svg_rec = svg.append("g").attr("class", "rec"); // main plot
const svg_leg = svg.append("g").attr("class", "leg"); // legend
const svg_hov = svg.append("g").attr("class", "hov"); // hover indicator

const x = d3
  .scaleBand()
  .domain(par.cat)
  .range([0, xMax])
  .paddingInner(0.1)
  .paddingOuter(0.05);
const y = d3.scaleLinear().domain([0, par.ymx]).range([yMax, 0]);

const x_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0," + yMax + ")")
  .call(d3.axisBottom(x));

const y_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0,0)")
  .call(d3.axisLeft(y));


const rec_bg = svg_bg
  .append("rect")
  .attr("width", xMax)
  .attr("height", yMax)
  .attr("fill", "#0078f01E")
  // .attr("opacity", 0.05)
  .style("pointer-events", "none");

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
  .style("pointer-events", "all");

//   //   //   //   //   //   //   //   //
// MOUSE

let dragging = false;
rec_clk
  .on("mousedown", (e) => {
    dragging = true;
  })
  .on("mousemove", (e) => {
    let [nx, ny] = d3.pointer(e);

    bar_op_hover(nx);

    hl_hov.attr("x2", nx).attr("y1", ny).attr("y2", ny).style("opacity", 1);

    if (dragging) {
      bar_edit(nx, ny);
    }
  })
  .on("mouseup", () => {
    dragging = false;
  })
  .on("mouseleave", () => {
    dragging = false;
    svg_rec.selectAll(".bar").attr("opacity", 1);
    hl_hov.style("opacity", 0);
  });

//   //   //   //   //   //   //   //   //
// FUNCTIONS

function create_bars() {
  create_legend();
  svg_rec.selectAll(".bar").remove();

  for (let ci = 0; ci < par.cat.length; ci++) {
    let c_n = "C" + (ci + 1);

    for (let vi = 0; vi < par.nv; vi++) {
      let v_n = "V" + (vi + 1);

      // let yr = Math.ceil(Math.random() * par.ymx);
      let yr = 5;

      svg_rec
        .append("rect")
        .attr("class", "bar")
        .attr("var_id", v_n)
        .attr("cat_id", c_n)
        .attr("x", x(c_n) + par.w_bar * vi)
        .attr("width", par.w_bar)
        .attr("y", y(yr))
        .attr("height", yMax - y(yr))
        .attr("fill", par.col[vi])
        .attr("ofill", par.col[vi])
        .attr("opacity", 1)
        .attr("stroke", "#333")
        .attr("stroke-width", 1);
    }
  }
}

function bar_op_hover(xcoord) {
  svg_rec.selectAll(".bar").attr("opacity", 0.6);

  let cat_close = null;
  for (let i = 0; i < par.cat.length; i++) {
    if (x(par.cat[i]) < xcoord) {
      cat_close = par.cat[i];
    }
  }
  svg_rec
    .selectAll(".bar")
    .filter(function () {
      return d3.select(this).attr("cat_id") === cat_close;
    })
    .attr("opacity", 0.9);
}

function bar_edit(xcoord, ycoord) {
  let ny = y(Math.round(y.invert(ycoord)));

  svg_rec.selectAll(".bar").each(function () {
    let bi = d3.select(this);
    let dx = xcoord - bi.attr("x");

    if (dx < par.w_bar && dx > 0) {
      bi.attr("y", ny).attr("height", yMax - ny);
    }
  });
}

function update_ax_x() {
  x.domain(par.cat);
  x_axis.transition().duration(500).call(d3.axisBottom(x));
  par.w_bar = x.bandwidth() / par.nv;
}

function update_ax_y() {
  y.domain([0, par.ymx]);
  y_axis.transition().duration(500).call(d3.axisLeft(y));

  svg_rec.selectAll(".bar").each(function () {
    let bi = d3.select(this);
    let pre_y = y.invert(bi.attr("y"));
    let ny = y(Math.round(pre_y));
    bi.attr("y", ny).attr("height", yMax - ny);
  });
}

function update_align(al) {
  let ny = null;

  if (al == "down") {
    ny = y(0);
  } else if(al == "mid") {
    ny = y(Math.round(par.ymx / 2));
  } else if(al == "up"){
    ny = y(par.ymx);
  } else {
    ny = y(1);
  }

  svg_rec.selectAll(".bar").each(function () {
    d3.select(this)
      .attr("y", ny)
      .attr("height", yMax - ny);
  });
}

function create_legend() {
  svg_leg.selectAll("rect").remove();
  svg_leg.selectAll("circle").remove();
  svg_leg.selectAll("text").remove();

  svg_leg
    .append("rect")
    .attr("x", xMax - 50)
    .attr("width", 50)
    .attr("y", 5)
    .attr("height", 20 * par.nv + 5)
    .attr("fill", "#ccc")
    .attr("opacity", 0.6);

  for (let i = 0; i < par.nv; i++) {
    svg_leg
      .append("circle")
      .attr("cx", xMax - 40)
      .attr("cy", 20 * i + 20)
      .attr("r", 6)
      .style("fill", par.col[i]);

    svg_leg
      .append("text")
      .attr("x", xMax - 30)
      .attr("y", 20 * i + 20)
      .attr("fill", "#333")
      .text("V" + (i + 1))
      .style("font-size", "15px")
      .attr("alignment-baseline", "middle");
  }
}
