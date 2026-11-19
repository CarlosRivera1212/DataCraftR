# Histogram tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/histogram.js.

#' Draw histograms and get a random sample that matches them
#'
#' Opens the Histogram gadget. Paint the bar heights (relative weights, i.e.
#' the shape of the population) for one histogram per variable, then press
#' **Done** to get a random sample of size `n` from that population.
#'
#' @param variables Initial variable names (1 to 10, unique, non-empty).
#' @param n Sample size, a whole number from 1 to 1e6.
#' @param xlim Initial x range: two finite numbers, increasing.
#' @param nbins Number of bins, a whole number from 1 to 100.
#' @return A data.frame with one numeric column per variable (variables with
#'   all-zero bars are dropped with a warning), carrying its spec (see
#'   [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_histogram(c("control", "treated"), n = 500, xlim = c(0, 100))
#' }
#' @export
dcr_histogram <- function(variables = "V1", n = 100, xlim = c(0, 10),
                          nbins = 10) {
  opts <- list(variables = check_names(variables, "variables"),
               n = histogram_check_n(n),
               xlim = as.numeric(check_range(xlim, "xlim")),
               nbins = histogram_check_nbins(nbins))
  run_dcr_gadget(histogram_tool(opts), "console")
}

#' Histogram addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_histogram_addin <- function() {
  run_dcr_gadget(histogram_tool(), "addin")
  invisible()
}

# A whole sample size in 1..1e6, else an error.
histogram_check_n <- function(n) {
  n <- suppressWarnings(as.numeric(n))
  if (length(n) != 1L || !is.finite(n) || n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  n
}

# A whole number of bins in 1..100, else an error.
histogram_check_nbins <- function(nbins) {
  nbins <- suppressWarnings(as.numeric(nbins))
  if (length(nbins) != 1L || !is.finite(nbins) || nbins != round(nbins) ||
      nbins < 1 || nbins > 100) {
    stop("nbins must be a whole number from 1 to 100.", call. = FALSE)
  }
  nbins
}

#' @noRd
histogram_tool <- function(options = list()) {
  defaults <- list(variables = "V1", n = 100, xlim = c(0, 10), nbins = 10)
  new_dcr_tool(
    "histogram", title = "Histogram", sidebar = histogram_sidebar,
    controls = c("variables", "active", "n", "xlim", "nbins"),
    options = utils::modifyList(defaults, options),
    validate = histogram_validate
  )
}

histogram_validate <- function(key, value, ...) {
  switch(
    key,
    variables = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "variables")
    },
    xlim = check_range(as.numeric(unlist(value)), key),
    n = histogram_check_n(unlist(value)),
    nbins = histogram_check_nbins(unlist(value)),
    value
  )
}

histogram_sidebar <- function(options) {
  tags <- htmltools::tags
  vars <- options$variables
  k <- length(vars)
  htmltools::tagList(
    dcr_section("Active variable"),
    dcr_seg_input("ctl_active", NULL,
                  stats::setNames(as.character(seq_len(k)), vars),
                  selected = "1", colors = dcr_palette(k),
                  aria_label = "Active variable"),
    shiny::textInput("ctl_variables", "Variables (comma-separated)",
                     paste(vars, collapse = ", "), updateOn = "blur"),
    dcr_section("Sample"),
    shiny::numericInput("ctl_n", "Sample size (n)", value = options$n,
                        min = 1, max = 1e6, step = 1),
    dcr_section("Axes"),
    dcr_fields_input("ctl_xlim", "x range", options$xlim, type = "number"),
    shiny::numericInput("ctl_nbins", "Number of bins", value = options$nbins,
                        min = 1, max = 100, step = 1),
    dcr_section("Bars"),
    tags$div(
      class = "d-flex gap-2",
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "flat", "Flat"),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "reset", "Reset")
    )
  )
}
