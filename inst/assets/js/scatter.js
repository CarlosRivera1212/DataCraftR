console.log("Hello Scatter JS!!!");
// document.body.style.backgroundColor = "skyblue";

//let params = new Object();
let params = { ng: 3, g: "G1", c: "#000", s: 0.1, xm: 1, ym: 1 };

const xSize = 700;
const ySize = 700;
const margin = 30;
const xMax = xSize - margin * 2;
const yMax = ySize - margin * 2;

// SHINY EVENTS

Shiny.addCustomMessageHandler("update_params", (new_params) => {
  params = new_params;
  console.log(params);
});

Shiny.addCustomMessageHandler("reset_click", (msg) => {
  if (circ_list.length > 0) {
    circ_list.forEach(function (circ_grp) {
      circ_grp.forEach((c) => c.remove());
    });
    circ_list = [];
    circ_redo = [];

    data_count();
  }
});

Shiny.addCustomMessageHandler("undo_click", (msg) => {
  if (circ_list.length > 0) {
    const l = circ_list.pop();
    l.forEach((c) => c.remove());
    circ_redo.push(l);

    data_count();
  }
});

Shiny.addCustomMessageHandler("redo_click", (msg) => {
  if (circ_redo.length > 0) {
    const l = circ_redo.pop();
    l.forEach((c) => svg_rec.node().appendChild(c.node()));
    circ_list.push(l);

    data_count();
  }
});

Shiny.addCustomMessageHandler("data_click", (msg) => {
  if (circ_list.length > 0) {
    let cx = [];
    let cy = [];
    let cg = [];

    //let cx = circ_list.flatMap(g =>
    //  g.map(e => e._groups[0][0].attributes.cx.value)
    //);

    circ_list.forEach((g) => {
      g.forEach((e) => {
        cx.push(x.invert(e._groups[0][0].attributes.cx.value));
        cy.push(y.invert(e._groups[0][0].attributes.cy.value));
        cg.push(e._groups[0][0].attributes.grp.value);
      });
    });

    let data = { x: cx, y: cy, g: cg };
    Shiny.setInputValue("data_return", data);
    console.log("DATA RETURN", data);
  }
});

//   //   //   //   //   //   //   //   //
// PLOT

const svg = d3
  .select("#s_pp_id")
  .append("svg")
  .attr("width", xSize)
  .attr("height", ySize)
  .append("g")
  .attr("transform", "translate(" + margin + "," + margin + ")");

const svg_bg = svg.append("g").attr("class", "bg");
const svg_rec = svg.append("g").attr("class", "rec");
const svg_hov = svg.append("g").attr("class", "hov");

const x = d3.scaleLinear().domain([0, params.xm]).range([0, xMax]);
//svg.append("g").attr("transform", "translate(0," + yMax + ")").call(d3.axisBottom(x));
//svg.append("g").call(d3.axisTop(x));
svg_bg
  .append("g")
  .attr("transform", "translate(0," + yMax + ")")
  .call(d3.axisBottom(x));

const y = d3.scaleLinear().domain([0, params.ym]).range([yMax, 0]);
svg_bg.append("g").call(d3.axisLeft(y));

const cir_hov = svg_hov
  .append("circle")
  .attr("r", xMax / 2)
  .attr("fill", "none")
  .attr("stroke", "#666666")
  .attr("stroke-width", 1)
  .style("pointer-events", "none")
  .style("opacity", 0.1);

const rec_clk = svg_rec
  .append("rect")
  .attr("width", xMax)
  .attr("height", yMax)
  .style("fill", "#0078f01E")
  .style("pointer-events", "all");

let circ_list = [];
let circ_last = [];
let circ_redo = [];
let dragging = false;
let circ_grp = 0;
let data_last = [];

rec_clk
  .on("mousedown", (event) => {
    dragging = true;
    circ_redo = [];
    circ_grp++;

    const [mx, my] = d3.pointer(event);
    const xVal = x.invert(mx);
    const yVal = y.invert(my);
    //console.log('Click en:', xVal, yVal);
    //console.log('N grp points: ', circ_grp);
  })
  .on("mousemove", (event) => {
    const [mx, my] = d3.pointer(event);
    cir_hov
      .attr("r", (xMax / 2) * params.s)
      .attr("cx", mx)
      .attr("cy", my)
      //.raise()
      .style("opacity", 1);

    if (dragging) {
      r = params.s * (xMax / 2) * Math.sqrt(Math.random());
      t = 2 * Math.PI * Math.random();
      rmx = mx + r * Math.cos(t);
      rmy = my + r * Math.sin(t);

      if (rmx >= 0 && rmx <= xMax && rmy >= 0 && rmy <= yMax) {
        const new_circ = svg_rec
          .append("circle")
          .attr("cx", rmx)
          .attr("cy", rmy)
          .attr("r", 5)
          .attr("stroke", "#666666")
          .attr("fill", params.c)
          .attr("grp", params.g)
          .style("pointer-events", "none")
          .style("opacity", 0.9);

        circ_last.push(new_circ);
        // data.push({x:x.invert(rmx), y:y.invert(rmy), g:params.g});

        data_count();
      }
    }
  })
  .on("mouseup", () => {
    dragging = false;
    if (circ_last.length > 0) {
      circ_list.push(circ_last);
      circ_last = [];
    }
    data_count();
  })
  .on("mouseleave", () => {
    dragging = false;
    if (circ_last.length > 0) {
      circ_list.push(circ_last);
      circ_last = [];
    }
  });

// FUNCTIONS
function data_count() {
  const txt = document.getElementById("s_txt_id");
  arr_len = circ_list.map((arr) => arr.length);
  tot_len = 0;
  for (let i of arr_len) {
    tot_len += i;
  }
  txt.textContent = tot_len + circ_last.length;
}

// Shiny.addCustomMessageHandler("reload_js", function(message) {
//   // Limpia el svg
//   d3.select("#s_pp_id").selectAll("*").remove();

//   // Vuelve a ejecutar tu inicialización de scatter
//   initScatter();
// });
