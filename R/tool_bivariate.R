# Bivariate normal tool: sidebar, control validation and the public entry
# points. The drawing itself lives in inst/www/dcr/tools/bivariate.js.

#' Draw bivariate normal populations and get a random sample from them
#'
#' Opens the Bivariate gadget. Drag the centre, the major handle and the minor
#' handle of each group's ellipse to shape a bivariate normal population (up to
#' ten groups), then press **Done** to get a random sample of size `n` per
#' group.
#'
#' @param groups Initial group names (1 to 10, unique, non-empty).
#' @param n Sample size per group, a whole number from 1 to 1e6 (with `n`
#'   times the number of groups at most 1e6).
#' @param xlim,ylim Initial axis ranges: two finite numbers, increasing.
#' @param names Column names for x, y and group: a character vector of
#'   length 3, named `x`, `y`, `group` or in that order.
#' @return A data.frame with x, y and a group factor whose levels are the
#'   groups, carrying its spec (see [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_bivariate(c("control", "treated"), n = 300)
#' }
#' @export
dcr_bivariate <- function(groups = c("A", "B"), n = 200,
                          xlim = c(0, 10), ylim = c(0, 10),
                          names = c(x = "x", y = "y", group = "group")) {
  groups <- check_names(groups, "groups")
  n <- histogram_check_n(n)
  if (n * length(groups) > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  opts <- list(groups = groups, n = n,
               xlim = as.numeric(check_range(xlim, "xlim")),
               ylim = as.numeric(check_range(ylim, "ylim")),
               names = scatter_names(names))
  run_dcr_gadget(bivariate_tool(opts), "console")
}

#' Bivariate addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_bivariate_addin <- function() {
  run_dcr_gadget(bivariate_tool(), "addin")
  invisible()
}

#' @noRd
bivariate_tool <- function(options = list()) {
  defaults <- list(groups = c("A", "B"), n = 200,
                   xlim = c(0, 10), ylim = c(0, 10),
                   names = list(x = "x", y = "y", group = "group"),
                   mode = "handles", autofit = TRUE)
  new_dcr_tool(
    "bivariate", title = "Bivariate normal", sidebar = bivariate_sidebar,
    controls = c("groups", "active", "mode", "autofit", "n", "xlim", "ylim",
                 "names"),
    options = utils::modifyList(defaults, options),
    validate = bivariate_validate
  )
}

bivariate_validate <- function(key, value, ...) {
  switch(
    key,
    groups = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "groups")
    },
    xlim = ,
    ylim = check_range(as.numeric(unlist(value)), key),
    n = histogram_check_n(unlist(value)),
    names = scatter_names(unlist(value)),
    value
  )
}

bivariate_sidebar <- function(options) {
  tags <- htmltools::tags
  groups <- options$groups
  k <- length(groups)
  htmltools::tagList(
    dcr_section("Active group"),
    dcr_seg_input("ctl_active", NULL,
                  stats::setNames(as.character(seq_len(k)), groups),
                  selected = "1", colors = dcr_palette(k),
                  aria_label = "Active group"),
    shiny::textInput("ctl_groups", "Groups (comma-separated)",
                     paste(groups, collapse = ", "), updateOn = "blur"),
    dcr_section("Editing"),
    dcr_seg_input("ctl_mode", NULL,
                  c(Handles = "handles", Gestures = "gestures"),
                  selected = options$mode, aria_label = "Editing mode",
                  icons = dcr_icons(handles = "handles", gestures = "gesture")),
    dcr_section("Sample"),
    shiny::numericInput("ctl_n", "Sample size per group (n)",
                        value = options$n, min = 1, max = 1e6, step = 1),
    dcr_section("Axes"),
    dcr_fields_input("ctl_xlim", "x range", options$xlim, type = "number"),
    dcr_fields_input("ctl_ylim", "y range", options$ylim, type = "number"),
    shiny::checkboxInput("ctl_autofit", "Fit axes automatically",
                         value = isTRUE(options$autofit)),
    dcr_action_button("reset-axes", "Reset axes", "axes"),
    dcr_section("Names"),
    dcr_fields_input("ctl_names", NULL, unlist(options$names))
  )
}
