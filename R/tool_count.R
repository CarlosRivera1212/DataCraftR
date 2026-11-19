# Count tool: sidebar, control validation and the public entry points.
# The drawing itself lives in inst/www/dcr/tools/count.js.

#' Draw count bars and get exactly those counts
#'
#' Opens the Count gadget. Paint the integer count of every (variable,
#' category) combination as grouped bars, then press **Done** to get a data
#' frame with exactly those counts: one row per observation, with factor
#' columns `variable` and `category` (levels in the drawn order).
#'
#' @param variables Initial variable names (1 to 10, unique, non-empty).
#' @param categories Initial category names (1 to 10, unique, non-empty).
#' @param ymax Initial top of the count axis, a whole number from 1 to 1e6.
#' @return A data.frame with factor columns `variable` and `category`, carrying
#'   its spec (see [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_count(c("control", "treated"), c("low", "mid", "high"))
#'   table(df)
#' }
#' @export
dcr_count <- function(variables = c("V1", "V2"),
                      categories = c("C1", "C2", "C3"), ymax = 20) {
  opts <- list(variables = check_names(variables, "variables"),
               categories = check_names(categories, "categories"),
               ymax = count_check_ymax(ymax))
  run_dcr_gadget(count_tool(opts), "console")
}

#' Count addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_count_addin <- function() {
  run_dcr_gadget(count_tool(), "addin")
  invisible()
}

# A whole number in 1..1e6, else an error.
count_check_ymax <- function(ymax) {
  ymax <- suppressWarnings(as.numeric(ymax))
  if (length(ymax) != 1L || !is.finite(ymax) || ymax != round(ymax) ||
      ymax < 1 || ymax > 1e6) {
    stop("ymax must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  ymax
}

# Split a comma-separated text (or a vector) into validated names.
count_split_names <- function(value, what) {
  txt <- paste(as.character(unlist(value)), collapse = ",")
  check_names(strsplit(txt, ",", fixed = TRUE)[[1]], what)
}

#' @noRd
count_tool <- function(options = list()) {
  defaults <- list(variables = c("V1", "V2"),
                   categories = c("C1", "C2", "C3"), ymax = 20)
  new_dcr_tool(
    "count", title = "Count", sidebar = count_sidebar,
    controls = c("variables", "categories", "ymax"),
    options = utils::modifyList(defaults, options),
    validate = count_validate
  )
}

count_validate <- function(key, value) {
  switch(
    key,
    variables = count_split_names(value, "variables"),
    categories = count_split_names(value, "categories"),
    ymax = count_check_ymax(unlist(value)),
    value
  )
}

count_sidebar <- function(options) {
  tags <- htmltools::tags
  htmltools::tagList(
    dcr_section("Levels"),
    shiny::textInput("ctl_variables", "Variables (comma-separated)",
                     paste(options$variables, collapse = ", "),
                     updateOn = "blur"),
    shiny::textInput("ctl_categories", "Categories (comma-separated)",
                     paste(options$categories, collapse = ", "),
                     updateOn = "blur"),
    dcr_section("Axes"),
    shiny::numericInput("ctl_ymax", "Y max", value = options$ymax,
                        min = 1, max = 1e6, step = 1),
    dcr_section("Bars"),
    tags$div(
      class = "d-flex flex-wrap gap-2",
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "align-top", "Align top"),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "align-middle", "Align middle"),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "align-bottom", "Align bottom")
    )
  )
}
