# Boxplot tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/boxplot.js.

#' Draw boxplots and get a random sample that matches them
#'
#' Opens the Boxplot gadget. Drag the first quartile, median and third
#' quartile of one box per variable, then press **Done** to get a random
#' sample of size `n` from a two-piece distribution with exactly those
#' quartiles.
#'
#' @param variables Initial variable names (1 to 10, unique, non-empty).
#' @param n Sample size, a whole number from 1 to 1e6.
#' @param family Shape of the distribution on each side of the median:
#'   `"normal"` or `"uniform"`.
#' @param ylim Initial value range: two finite numbers, increasing.
#' @return A data.frame with one numeric column per variable, carrying its
#'   spec (see [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_boxplot(c("control", "treated"), n = 200, ylim = c(0, 100))
#' }
#' @export
dcr_boxplot <- function(variables = c("V1", "V2", "V3"), n = 100,
                        family = c("normal", "uniform"), ylim = c(0, 10)) {
  family <- match.arg(family)
  opts <- list(variables = check_names(variables, "variables"),
               n = boxplot_check_n(n),
               family = family,
               ylim = as.numeric(check_range(ylim, "ylim")))
  run_dcr_gadget(boxplot_tool(opts), "console")
}

#' Boxplot addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_boxplot_addin <- function() {
  run_dcr_gadget(boxplot_tool(), "addin")
  invisible()
}

# A whole sample size in 1..1e6, else an error.
boxplot_check_n <- function(n) {
  n <- suppressWarnings(as.numeric(n))
  if (length(n) != 1L || !is.finite(n) || n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  n
}

#' @noRd
boxplot_tool <- function(options = list()) {
  defaults <- list(variables = c("V1", "V2", "V3"), n = 100,
                   family = "normal", ylim = c(0, 10))
  new_dcr_tool(
    "boxplot", title = "Boxplot", sidebar = boxplot_sidebar,
    controls = c("variables", "active", "n", "family", "ylim"),
    options = utils::modifyList(defaults, options),
    validate = boxplot_validate
  )
}

boxplot_validate <- function(key, value, ...) {
  switch(
    key,
    variables = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "variables")
    },
    ylim = check_range(as.numeric(unlist(value)), key),
    n = boxplot_check_n(unlist(value)),
    family = {
      f <- unlist(value)
      if (!is.character(f) || length(f) != 1L ||
          !f %in% c("normal", "uniform")) {
        stop("family must be \"normal\" or \"uniform\".", call. = FALSE)
      }
      f
    },
    value
  )
}

boxplot_sidebar <- function(options) {
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
    dcr_seg_input("ctl_family", "Distribution",
                  c(Normal = "normal", Uniform = "uniform"),
                  selected = options$family,
                  icons = dcr_icons(normal = "normal", uniform = "flat")),
    dcr_section("Axes"),
    dcr_fields_input("ctl_ylim", "y range", options$ylim, type = "number"),
    dcr_section("Boxes"),
    tags$div(
      class = "d-flex gap-2",
      dcr_action_button("align", "Align medians", "medians"),
      dcr_action_button("reset", "Reset boxes", "reset")
    )
  )
}
