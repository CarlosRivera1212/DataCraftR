# Density tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/density.js.

#' Sculpt density curves and get a random sample that matches them
#'
#' Opens the Density gadget. Shape a smooth density curve for each variable
#' with a soft brush (**Pull** drags the curve up or down around the point you
#' press, **Paint** moves it towards the cursor height), then press **Done**
#' to get a random sample of size `n` from that distribution.
#'
#' @param variables Initial variable names (1 to 10, unique, non-empty).
#' @param n Sample size, a whole number from 1 to 1e6.
#' @param xlim Initial x range: two finite numbers, increasing.
#' @return A data.frame with one numeric column per variable (variables with
#'   an all-zero curve are dropped with a warning), carrying its spec (see
#'   [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_density(c("control", "treated"), n = 500, xlim = c(0, 100))
#' }
#' @export
dcr_density <- function(variables = "V1", n = 100, xlim = c(0, 10)) {
  opts <- list(variables = check_names(variables, "variables"),
               n = histogram_check_n(n),
               xlim = as.numeric(check_range(xlim, "xlim")))
  run_dcr_gadget(density_tool(opts), "console")
}

#' Density addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_density_addin <- function() {
  run_dcr_gadget(density_tool(), "addin")
  invisible()
}

#' @noRd
density_tool <- function(options = list()) {
  defaults <- list(variables = "V1", n = 100, xlim = c(0, 10),
                   mode = "pull", brush = 0.12)
  new_dcr_tool(
    "density", title = "Density", sidebar = density_sidebar,
    controls = c("variables", "active", "mode", "brush", "n", "xlim"),
    options = utils::modifyList(defaults, options),
    validate = density_validate
  )
}

density_validate <- function(key, value) {
  switch(
    key,
    variables = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "variables")
    },
    xlim = check_range(as.numeric(unlist(value)), key),
    n = histogram_check_n(unlist(value)),
    value
  )
}

density_sidebar <- function(options) {
  tags <- htmltools::tags
  vars <- options$variables
  k <- length(vars)
  action <- function(name, label) {
    tags$button(type = "button", class = "btn btn-light btn-sm",
                `data-dcr-action` = name, label)
  }
  htmltools::tagList(
    dcr_section("Active variable"),
    dcr_seg_input("ctl_active", NULL,
                  stats::setNames(as.character(seq_len(k)), vars),
                  selected = "1", colors = dcr_palette(k),
                  aria_label = "Active variable"),
    shiny::textInput("ctl_variables", "Variables (comma-separated)",
                     paste(vars, collapse = ", "), updateOn = "blur"),
    dcr_section("Brush"),
    dcr_seg_input("ctl_mode", NULL, c(Pull = "pull", Paint = "paint"),
                  selected = options$mode, aria_label = "Brush mode"),
    # Width as a fraction of the x range (sigma = brush * diff(xlim)), so it
    # follows xlim changes by itself.
    shiny::sliderInput("ctl_brush",
                       tags$span("Width ", tags$span(class = "dcr-kbd", "[ ]")),
                       min = 0.005, max = 1, value = options$brush,
                       step = 0.005, ticks = FALSE),
    dcr_section("Sample"),
    shiny::numericInput("ctl_n", "Sample size (n)", value = options$n,
                        min = 1, max = 1e6, step = 1),
    dcr_section("Axes"),
    dcr_fields_input("ctl_xlim", "x range", options$xlim, type = "number"),
    dcr_section("Shape"),
    tags$div(
      class = "d-flex gap-2",
      action("bell", "Bell"), action("flat", "Flat"), action("skew", "Skewed")
    )
  )
}
