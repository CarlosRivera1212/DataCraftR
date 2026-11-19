# Scatter tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/scatter.js.

#' Draw a scatter plot and get its points as a data frame
#'
#' Opens the Scatter gadget. Spray, place or erase points for up to ten
#' groups, then press **Done** to get exactly the drawn points.
#'
#' @param xlim,ylim Initial axis ranges: two finite numbers, increasing.
#' @param groups Initial group names (1 to 10, unique, non-empty).
#' @param names Column names for x, y and group: a character vector of
#'   length 3, named `x`, `y`, `group` or in that order.
#' @return A data.frame with the drawn points (x, y and a group factor whose
#'   levels are the groups), carrying its spec (see [dcr_spec()]); `NULL`
#'   invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_scatter(xlim = c(-5, 5), groups = c("control", "treated"))
#' }
#' @export
dcr_scatter <- function(xlim = c(0, 10), ylim = c(0, 10),
                        groups = c("A", "B", "C"),
                        names = c(x = "x", y = "y", group = "group")) {
  opts <- list(xlim = as.numeric(check_range(xlim, "xlim")),
               ylim = as.numeric(check_range(ylim, "ylim")),
               groups = check_names(groups, "groups"),
               names = scatter_names(names))
  run_dcr_gadget(scatter_tool(opts), "console")
}

#' Scatter addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_scatter_addin <- function() {
  run_dcr_gadget(scatter_tool(), "addin")
  invisible()
}

# x, y, group names as a named list in that order, validated.
scatter_names <- function(names) {
  keys <- c("x", "y", "group")
  if (!is.null(names(names)) && setequal(names(names), keys)) {
    names <- names[keys]
  }
  if (length(names) != 3L) {
    stop("names must have x, y and group.", call. = FALSE)
  }
  nms <- check_names(as.character(unlist(names, use.names = FALSE)), "names")
  stats::setNames(as.list(nms), keys)
}

#' @noRd
scatter_tool <- function(options = list()) {
  defaults <- list(xlim = c(0, 10), ylim = c(0, 10),
                   groups = c("A", "B", "C"),
                   names = list(x = "x", y = "y", group = "group"),
                   mode = "spray", brush = 0.08, density = 40)
  new_dcr_tool(
    "scatter", title = "Scatter", sidebar = scatter_sidebar,
    controls = c("groups", "active", "mode", "brush", "density",
                 "xlim", "ylim", "names"),
    options = utils::modifyList(defaults, options),
    validate = scatter_validate
  )
}

scatter_validate <- function(key, value, ...) {
  switch(
    key,
    groups = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "groups")
    },
    xlim = ,
    ylim = check_range(as.numeric(unlist(value)), key),
    names = scatter_names(unlist(value)),
    value
  )
}

scatter_sidebar <- function(options) {
  tags <- htmltools::tags
  groups <- options$groups
  n <- length(groups)
  htmltools::tagList(
    dcr_section("Active group"),
    dcr_seg_input("ctl_active", NULL,
                  stats::setNames(as.character(seq_len(n)), groups),
                  selected = "1", colors = dcr_palette(n),
                  aria_label = "Active group"),
    shiny::textInput("ctl_groups", "Groups (comma-separated)",
                     paste(groups, collapse = ", "), updateOn = "blur"),
    dcr_section("Brush"),
    dcr_seg_input("ctl_mode", NULL,
                  c(Spray = "spray", Point = "point", Erase = "erase"),
                  selected = options$mode, aria_label = "Brush mode"),
    shiny::sliderInput("ctl_brush",
                       tags$span("Size ", tags$span(class = "dcr-kbd", "[ ]")),
                       min = 0.01, max = 0.5, value = options$brush,
                       step = 0.01, ticks = FALSE),
    shiny::sliderInput("ctl_density", "Density (points/s)", min = 5, max = 200,
                       value = options$density, step = 5, ticks = FALSE),
    dcr_section("Axes"),
    dcr_fields_input("ctl_xlim", "x range", options$xlim, type = "number"),
    dcr_fields_input("ctl_ylim", "y range", options$ylim, type = "number"),
    dcr_section("Names"),
    dcr_fields_input("ctl_names", NULL, unlist(options$names))
  )
}
