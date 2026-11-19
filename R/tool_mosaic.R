# Mosaic tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/mosaic.js.

#' Draw a two-way contingency table and get exactly those counts
#'
#' Opens the Mosaic gadget. Drag the vertical borders between columns to move
#' observations between two columns (each keeps its row proportions) and drag
#' the horizontal cuts inside a column to shift counts between its blocks.
#' Everything snaps to whole counts and the total stays exactly `n`. Press
#' **Done** to get a data frame with exactly those counts: one row per
#' observation, with two factor columns (levels in the drawn order).
#'
#' @param cols,rows Initial category names of the column and row variables (2
#'   to 10 each, unique, non-empty).
#' @param n Total number of observations, a whole number from 1 to 1e6. The
#'   table starts uniform.
#' @param names Names of the two output columns: a character vector of length
#'   2, named `col`, `row` or in that order.
#' @return A data.frame with two factor columns named by `names` (column
#'   variable first), carrying its spec (see [dcr_spec()]); `NULL` invisibly on
#'   Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_mosaic(c("No", "Yes"), c("Healthy", "Sick"), n = 300)
#'   table(df)
#' }
#' @export
dcr_mosaic <- function(cols = c("No", "Yes"), rows = c("Healthy", "Sick"),
                       n = 200, names = c(col = "exposure", row = "outcome")) {
  opts <- list(cols = mosaic_split_names(cols, "cols"),
               rows = mosaic_split_names(rows, "rows"),
               n = mosaic_check_n(n),
               names = mosaic_names(names))
  run_dcr_gadget(mosaic_tool(opts), "console")
}

#' Mosaic addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_mosaic_addin <- function() {
  run_dcr_gadget(mosaic_tool(), "addin")
  invisible()
}

# A whole number in 1..1e6, else an error.
mosaic_check_n <- function(n) {
  n <- suppressWarnings(as.numeric(n))
  if (length(n) != 1L || !is.finite(n) || n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  n
}

# Split a comma-separated text (or a vector) into 2 to 10 validated names.
mosaic_split_names <- function(value, what) {
  txt <- paste(as.character(unlist(value)), collapse = ",")
  mosaic_check_cats(strsplit(txt, ",", fixed = TRUE)[[1]], what)
}

#' @noRd
mosaic_tool <- function(options = list()) {
  defaults <- list(cols = c("No", "Yes"), rows = c("Healthy", "Sick"),
                   n = 200, names = list(col = "exposure", row = "outcome"))
  new_dcr_tool(
    "mosaic", title = "Mosaic", sidebar = mosaic_sidebar,
    controls = c("cols", "rows", "n", "names"),
    options = utils::modifyList(defaults, options),
    validate = mosaic_validate
  )
}

mosaic_validate <- function(key, value) {
  switch(
    key,
    cols = mosaic_split_names(value, "cols"),
    rows = mosaic_split_names(value, "rows"),
    n = mosaic_check_n(unlist(value)),
    names = mosaic_names(unlist(value)),
    value
  )
}

mosaic_sidebar <- function(options) {
  tags <- htmltools::tags
  htmltools::tagList(
    dcr_section("Table"),
    shiny::numericInput("ctl_n", "Total observations (N)",
                        value = options$n, min = 1, max = 1e6, step = 1),
    shiny::textInput("ctl_cols", "Column categories (comma-separated)",
                     paste(options$cols, collapse = ", "),
                     updateOn = "blur"),
    shiny::textInput("ctl_rows", "Row categories (comma-separated)",
                     paste(options$rows, collapse = ", "),
                     updateOn = "blur"),
    dcr_section("Shape"),
    tags$div(
      class = "d-flex flex-wrap gap-2",
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "independent", "Independent"),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "uniform", "Uniform")
    ),
    dcr_section("Names"),
    dcr_fields_input("ctl_names", NULL, unlist(options$names))
  )
}
