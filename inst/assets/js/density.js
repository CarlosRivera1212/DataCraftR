console.log("Hello Density JS www!!!");

let par = {
  nv: 3,
  v: "V1",
  stp: 0.1,
  points: [],
  col: ["#ff0000", "#00ff00", "#0000ff"],
};

const xSize = 500;
const ySize = 500;
const margin = 30;
const xMax = xSize - margin * 3;
const yMax = ySize - margin * 2;

let den_list = [];

//   //   //   //   //   //   //   //   //
// SHINY EVENTS
Shiny.addCustomMessageHandler("update_params", (new_par) => {
    par.nv = new_par.nv;
    par.stp = new_par.stp;
    par.col = new_par.col;
    
    par.points = [];
    // for (let i of new_par.points) {
    //     par.points.push({ x: +i, y: 0 });
    // }
    for (let i = 0; i <= par.stp; i += 1) {
        par.points.push({ x: +i/par.stp, y: 0 });
    }
    init_density();
    // update_points();
});

Shiny.addCustomMessageHandler("update_v", (new_v) => {
    par.v = new_v.v;
    update_points();
});

Shiny.addCustomMessageHandler("reset", (al) => {
  init_density();
  update_points();
});
Shiny.addCustomMessageHandler("alup", (al) => {
    align_density(1);
});
Shiny.addCustomMessageHandler("aldw", (al) => {
    align_density(0);
});


//   //   //   //   //   //   //   //   //
// INIT PLOT

const svg = d3
  .select("#d_pp_id")
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
  .scaleLinear()
  .domain([0, 1])
  .range([0, xMax]);
const y = d3
    .scaleLinear()
    .domain([0, 1])
    .range([yMax, 0]);

const x_axis = svg_bg
  .append("g")
  .attr("transform", "translate(0," + yMax + ")")
  .call(d3.axisBottom(x));

// const y_axis = svg_bg
//   .append("g")
//   .attr("transform", "translate(0,0)")
//   .call(d3.axisLeft(y));

const rec_bg = svg_bg
  .append("rect")
  .attr("width", xMax)
  .attr("height", yMax)
  .attr("fill", "#0078f01E")
  .style("pointer-events", "none");

const hl_hov = svg_hov
  .append("line")
  .attr("x1", x(0))
  .attr("stroke", "#666")
  .attr("stroke-width", 1)
  .style("pointer-events", "none");

//   //   //   //   //   //   //   //   //
// MOUSE

function enable_density_drag(den_line, den_point, line) {
    const drag = d3.drag()
        .on("drag", function (e, d) {
            const [px, py] = d3.pointer(e, svg_rec.node());

            if (py < 0 || py > yMax) return;

            d.y = y.invert(py);
            d3.select(this).attr("cy", py);
            den_line.attr("d", line);
        });

    den_point.call(drag);
}

//   //   //   //   //   //   //   //   //
// FUNCTIONS
function create_density(v, col, p) {
    const p_v = p.map(d => ({ ...d }));

    const new_den = svg_rec
        .append("g")
        .attr("class", "den")
        .attr("var", "V" + v);

    let line = d3.line()
        .x(d => x(d.x))
        .y(d => y(d.y))
        // .curve(d3.curveCatmullRom.alpha(1.0));
        // .curve(d3.curveBundle.beta(1.0));
        // .curve(d3.curveCardinal);
        // .curve(d3.curveBumpX);
        .curve(d3.curveMonotoneX);

    const den_line = new_den
        .append("path")
        .attr("class", "line")
        .datum(p_v)
        .attr("d", line)
        .attr("fill", "none")
        .attr("stroke", col)
        .attr("stroke-width", 2)
        .style("pointer-events", "none");

        
    const den_point = new_den.selectAll(".point")
        .data(p_v)
        .enter()
        .append("circle")
        .attr("class", "point")
        .attr("r", 6)
        .attr("cx", d => x(d.x))
        .attr("cy", d => y(d.y))
        .attr("fill", col)
        .attr("cursor", "grab");

    enable_density_drag(den_line, den_point, line);
    return { new_den, den_line, den_point, line };
}

function init_density() {
    svg_rec.selectAll(".den").remove();
    for (let i = 0; i < par.nv; i++) {
        // den_list.push(create_density(i + 1, par.col[i], par.points));
        create_density(i + 1, par.col[i], par.points);
    }
}


function update_points() {
    // for (let i = 0; i < den_list.length; i++) {
    //     v_i = den_list[i].new_den.attr("var");
    //     if (v_i == par.v) {
    //         den_list[i].den_point.attr("r", 6);
    //     } else {
    //         den_list[i].den_point.attr("r", 0);
    //     }
    // }
    svg_rec.selectAll(".den").each(function () {
        const di = d3.select(this);
        if (di.attr("var") == par.v) {
            di.selectAll(".point").attr("r", 6);
        } else {
            di.selectAll(".point").attr("r", 0);
        }
    });
}

// init_density();
// update_points();

function align_density(val) {
    // den_i.den_point.each(d => d.y = val);
    // den_i.den_point.attr("cy", y(val));
    // den_i.den_line.attr("d", den_i.line);

    const line = d3.line()
        .x(d => x(d.x))
        .y(d => y(d.y))
        .curve(d3.curveMonotoneX);

    svg_rec.selectAll(".den").each(function () {
        const di = d3.select(this);
        if (di.attr("var") == par.v) {
            di.selectAll(".point").each(d => d.y = val);
            di.selectAll(".point").attr("cy", y(val));
            di.select(".line").attr("d", d => line(d));
        } else {
            di.selectAll(".point").attr("r", 0);
        }
    });
}

// let line = d3.line()
//   .x(d => x(d.x))
//   .y(d => y(d.y))
//   .curve(d3.curveCatmullRom.alpha(1.0));

// let path = svg.append("path")
//   .datum(points)
//   .attr("d", line)
//   .attr("fill", "none")
//   .attr("stroke", "red")
//   .attr("stroke-width", 2);

// // Dibujamos los puntos de control
// const handles = svg.selectAll(".handle")
//   .data(points)
//   .enter()
//   .append("circle")
//   .attr("class", "handle")
//   .attr("r", 6)
//   .attr("cx", d => x(d.x))
//   .attr("cy", d => y(d.y))
//   .attr("fill", "blue")
//   .call(
//     d3.drag()
//       .on("drag", function (event, d) {
//         const [nx, ny] = d3.pointer(event);
//         const xVal = x.invert(nx);
//         const yVal = y.invert(ny);
//         d.x = xVal;
//         d.y = yVal;
//         d3.select(this)
//           .attr("cx", x(d.x))
//           .attr("cy", y(d.y));

//         path.attr("d", line); // Recalcula la curva
//       })
//   );



//   //   //   //   //   //   //   //   //
// LINE GENERATOR - Interpolación suave Catmull-Rom

// const line = d3.line()
// //   .curve(d3.curveCatmullRom)
// //   .curve(d3.curveCatmullRom.alpha(1.0))
//   .curve(d3.curveBundle)
// //   .curve(d3.curveCardinal)
//   .x(d => x(d.x))
//   .y(d => y(d.y));


//   svg_rec.append("path")
//     .datum([
//       { x: 0.0, y: 0.0 }, 
//       { x: 0.4, y: 0.2 },
//       { x: 0.5, y: 0.5 }, 
//       { x: 1.0, y: 0.0 },])
//     .attr("d", line)
//     .attr("fill", "none")
//     .attr("stroke", "#ff0000")
//     .attr("stroke-width", 2)
//     .style("pointer-events", "none");


//     svg_rec.append("path")
//       .datum(densityPoints)
//       .attr("d", line)
//       .attr("fill", "none")
//       .attr("stroke", params.col[0])
//       .attr("stroke-width", 2)
//       .style("pointer-events", "none");
// //   //   //   //   //   //   //   //   //
// // INICIALIZAR CURVA

// function initDensityCurve() {
//   // Comenzar sin puntos - solo la curva base en los extremos
//   densityPoints = [
//     { x: params.xmn, y: 0 },
//     { x: params.xmx, y: 0 }
//   ];
//   redraw();
// }

// //   //   //   //   //   //   //   //   //
// // REDRAW

// function redraw() {
//   // Dibujar la línea de densidad
//   svg_rec.selectAll("path").remove();
//   if (densityPoints.length > 1) {
//     svg_rec.append("path")
//       .datum(densityPoints)
//       .attr("d", line)
//       .attr("fill", "none")
//       .attr("stroke", params.col[0])
//       .attr("stroke-width", 2)
//       .style("pointer-events", "none");
//   }

//   // Dibujar puntos de control con drag
//   const circles = svg_points.selectAll("circle")
//     .data(densityPoints, (d, i) => `${d.x}-${d.y}`);
  
//   circles.remove();
  
//   circles
//     .enter()
//     .append("circle")
//     .attr("cx", d => x(d.x))
//     .attr("cy", d => y(d.y))
//     .attr("r", 6)
//     .attr("fill", "#1f77b4")
//     .attr("stroke", "white")
//     .attr("stroke-width", 2)
//     .style("cursor", "grab")
//     .style("pointer-events", "all")
//     .style("z-index", "10")
//     .on("mousedown", function(e) {
//       e.stopPropagation();
//     })
//     .call(
//       d3.drag()
//         .on("start", function(e) {
//           d3.select(this)
//             .style("cursor", "grabbing")
//             .attr("r", 7)
//             .attr("fill", "#ff6b6b");
//         })
//         .on("drag", function(e, d) {
//           const [nx, ny] = d3.pointer(e);
//           const yVal = y.invert(ny);

//           if (yVal >= 0 && yVal <= params.ymx) {
//             d.y = yVal;
            
//             d3.select(this).attr("cy", y(d.y));
            
//             svg_rec.selectAll("path").remove();
//             svg_rec.append("path")
//               .datum(densityPoints)
//               .attr("d", line)
//               .attr("fill", "none")
//               .attr("stroke", params.col[0])
//               .attr("stroke-width", 2)
//               .style("pointer-events", "none");
//           }
//         })
//         .on("end", function(e) {
//           d3.select(this)
//             .style("cursor", "grab")
//             .attr("r", 6)
//             .attr("fill", "#1f77b4");
//         })
//     );
// }

// function update_ax() {
//   x.domain([params.xmn, params.xmx]);
//   y.domain([0, params.ymx]);
  
//   svg_bg.select(".x-axis")
//     .transition()
//     .call(d3.axisBottom(x));
  
//   svg_bg.select(".y-axis")
//     .transition()
//     .call(d3.axisLeft(y));
  
//   redraw();
// }

// //   //   //   //   //   //   //   //   //
// // MOUSE EVENTS

// rec_clk
//   .on("click", (e) => {
//     // Agregar nuevo punto en la posición del click
//     let [nx, ny] = d3.pointer(e);
//     const xVal = x.invert(nx);
//     const yVal = y.invert(ny);

//     // Asegurar que el punto esté dentro del rango válido
//     if (xVal >= params.xmn && xVal <= params.xmx && yVal >= 0 && yVal <= params.ymx) {
//       densityPoints.push({ x: xVal, y: yVal });
//       // Ordenar puntos por x para mantener la curva suave
//       densityPoints.sort((a, b) => a.x - b.x);
//       redraw();
//     }
//   });

// //   //   //   //   //   //   //   //   //
// // INICIALIZAR

// initDensityCurve();
