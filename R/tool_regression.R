# Regression tool: equation evaluation, sidebar, control validation and the
# public entry points. The drawing itself lives in
# inst/www/dcr/tools/regression.js.

# Number of grid points of a curve (spec: K = 201).
regression_k <- 201L

# Evaluate an equation (string in x, or function) on the grid `xs`. Returns a
# finite numeric vector of length(xs); undefined points take the nearest
# finite value and set attr "notice". Errors if nothing usable results.
regression_eval <- function(f, xs) {
  y <- if (is.function(f)) {
    suppressWarnings(f(xs))
  } else {
    if (!is.character(f) || length(f) != 1L || is.na(f) || !nzchar(trimws(f))) {
      stop("The equation must be a single non-empty string or a function.",
           call. = FALSE)
    }
    tryCatch(
      suppressWarnings(
        eval(parse(text = f), envir = list(x = xs, pi = pi), enclos = baseenv())
      ),
      error = function(e) {
        stop("Invalid equation: ", conditionMessage(e), call. = FALSE)
      }
    )
  }
  if (!is.numeric(y) || !(length(y) %in% c(1L, length(xs)))) {
    stop("The equation must return one value per x.", call. = FALSE)
  }
  if (length(y) == 1L) y <- rep(y, length(xs))
  y <- as.numeric(y)
  ok <- is.finite(y)
  if (!any(ok)) {
    stop("The equation is undefined on the whole x range.", call. = FALSE)
  }
  if (all(ok)) return(y)
  idx <- seq_along(y)
  good <- idx[ok]
  nearest <- good[vapply(idx[!ok], function(i) which.min(abs(good - i)),
                         integer(1))]
  y[!ok] <- y[nearest]
  attr(y, "notice") <- "The equation is undefined for some x; nearest values were used."
  y
}

# Per-group equations as a list of strings/functions, one per group.
regression_equations <- function(f, k) {
  if (is.function(f) || (is.character(f) && length(f) == 1L)) {
    return(rep(list(f), k))
  }
  f <- as.list(f)
  if (length(f) == 1L) return(rep(f, k))
  if (length(f) != k) {
    stop("f must be one equation or one per group.", call. = FALSE)
  }
  f
}

# Validate the arguments of dcr_regression() and build the tool options.
# Undefined-point notices become warnings; errors propagate.
regression_options <- function(f, groups, n, xlim, sd, names, shared_x) {
  groups <- check_names(groups, "groups")
  k <- length(groups)
  n <- histogram_check_n(n)
  if (n * k > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  xlim <- as.numeric(check_range(xlim, "xlim"))
  if (!is.numeric(sd) || anyNA(sd) || any(!is.finite(sd)) || any(sd < 0) ||
      !(length(sd) %in% c(1L, k))) {
    stop("sd must be finite and non-negative: one value or one per group.",
         call. = FALSE)
  }
  sd <- rep(as.numeric(sd), length.out = k)
  if (!is.logical(shared_x) || length(shared_x) != 1L || is.na(shared_x)) {
    stop("shared_x must be TRUE or FALSE.", call. = FALSE)
  }
  eqs <- regression_equations(f, k)
  xs <- seq(xlim[1], xlim[2], length.out = regression_k)
  fm <- matrix(0, nrow = k, ncol = regression_k)
  for (i in seq_len(k)) {
    y <- regression_eval(eqs[[i]], xs)
    notice <- attr(y, "notice", exact = TRUE)
    if (!is.null(notice)) {
      warning("group ", groups[i], ": the equation is undefined for some x; ",
              "nearest values were used.", call. = FALSE)
    }
    fm[i, ] <- as.numeric(y)
  }
  sm <- matrix(sd, nrow = k, ncol = regression_k)
  list(groups = groups, n = n, xlim = xlim, f = fm, s = sm, level = sd[1],
       level_max = max(1, 2 * max(sd), diff(range(fm)) / 2),
       names = regression_names(names), shared_x = shared_x)
}

#' Draw a regression curve with its error band and get a random sample
#'
#' Opens the Regression gadget. Shape the mean curve `f(x)` and the error
#' spread around it for each group (**Pull** and **Paint** brushes, or type an
#' equation), then press **Done** to get a random sample of size `n` per group.
#'
#' @param f The initial curve: one equation (a string in `x`, such as
#'   `"2 + 0.5 * x"`, or a function) used for every group, or one per group
#'   (a character vector or list). Points where an equation is undefined take
#'   the nearest finite value, with a warning.
#' @param groups Initial group names (1 to 10, unique, non-empty).
#' @param n Sample size per group, a whole number from 1 to 1e6 (with `n`
#'   times the number of groups at most 1e6).
#' @param xlim Initial x range: two finite numbers, increasing.
#' @param sd Initial error standard deviation: one value or one per group,
#'   each at least 0.
#' @param names Column names for x, y and group: a character vector of
#'   length 3, named `x`, `y`, `group` or in that order.
#' @details An equation given as a string or function is evaluated in R in
#'   your session, like any other R code you run.
#' @param shared_x If `TRUE` all groups share the same x values.
#' @return A data.frame with x, y and a group factor whose levels are the
#'   groups, carrying its spec (see [dcr_spec()]); `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_regression("2 + 0.5 * x", groups = c("control", "treated"))
#' }
#' @export
dcr_regression <- function(f = "x", groups = "A", n = 200, xlim = c(0, 10),
                           sd = 1,
                           names = c(x = "x", y = "y", group = "group"),
                           shared_x = TRUE) {
  opts <- regression_options(f, groups, n, xlim, sd, names, shared_x)
  run_dcr_gadget(regression_tool(opts), "console")
}

#' Regression addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_regression_addin <- function() {
  run_dcr_gadget(regression_tool(), "addin")
  invisible()
}

# Default options (also used by the addin).
regression_defaults <- function() {
  xs <- seq(0, 10, length.out = regression_k)
  list(groups = "A", n = 200, xlim = c(0, 10),
       f = matrix(xs, nrow = 1L), s = matrix(1, 1L, regression_k),
       level = 1, level_max = 5,
       names = list(x = "x", y = "y", group = "group"), shared_x = TRUE,
       target = "curve", mode = "pull", brush = 0.12)
}

#' @noRd
regression_tool <- function(options = list()) {
  new_dcr_tool(
    "regression", title = "Regression curve", sidebar = regression_sidebar,
    controls = c("groups", "active", "target", "mode", "brush", "equation",
                 "level", "shared_x", "xlim", "n", "names"),
    options = utils::modifyList(regression_defaults(), options),
    validate = regression_validate
  )
}

regression_validate <- function(key, value, ctl = list(), ...) {
  switch(
    key,
    groups = {
      txt <- paste(as.character(unlist(value)), collapse = ",")
      check_names(strsplit(txt, ",", fixed = TRUE)[[1]], "groups")
    },
    xlim = check_range(as.numeric(unlist(value)), key),
    n = histogram_check_n(unlist(value)),
    names = regression_names(unlist(value)),
    equation = {
      txt <- as.character(unlist(value))
      if (length(txt) == 0L || is.na(txt[1]) || !nzchar(trimws(txt[1]))) {
        # A cleared field: nothing to apply, nothing to complain about.
        stop(structure(class = c("dcr_skip", "error", "condition"),
                       list(message = "", call = NULL)))
      }
      # Evaluate on the grid of the xlim currently in the sidebar.
      xlim <- check_range(as.numeric(unlist(ctl$xlim)), "xlim")
      xs <- seq(xlim[1], xlim[2], length.out = regression_k)
      y <- regression_eval(txt[1], xs)
      out <- list(f = as.numeric(y))
      notice <- attr(y, "notice", exact = TRUE)
      if (!is.null(notice)) attr(out, "notice") <- notice
      out
    },
    value
  )
}

# Small inline SVG icon (24 x 14 viewBox) from path data, built with htmltools.
regression_icon <- function(d) {
  tags <- htmltools::tags
  tags$svg(
    xmlns = "http://www.w3.org/2000/svg", viewBox = "0 0 24 14", width = "24",
    height = "14", `aria-hidden` = "true", focusable = "false",
    tags$path(d = d, fill = "none", stroke = "currentColor",
              `stroke-width` = "1.6", `stroke-linecap` = "round")
  )
}

# 20 x 20 glyph for the segmented controls (prototype glyphs).
regression_seg_icon <- function(d, fill = FALSE) {
  tags <- htmltools::tags
  tags$svg(
    xmlns = "http://www.w3.org/2000/svg", viewBox = "0 0 20 20", width = "20",
    height = "20", `aria-hidden` = "true", focusable = "false", fill = "none",
    stroke = "currentColor", `stroke-width` = "1.5", `stroke-linecap` = "round",
    `stroke-linejoin` = "round",
    tags$path(d = d, fill = if (fill) "currentColor", `fill-opacity` = if (fill) "0.15")
  )
}

regression_sidebar <- function(options) {
  tags <- htmltools::tags
  groups <- options$groups
  k <- length(groups)
  shape <- function(action, label, d) {
    tags$button(type = "button", class = "btn btn-light btn-sm dcr-shape",
                `data-dcr-action` = action, title = label,
                `aria-label` = label, regression_icon(d))
  }
  example <- function(eq) {
    tags$button(type = "button", class = "btn btn-light btn-sm dcr-example",
                `data-equation` = eq, eq)
  }
  htmltools::tagList(
    dcr_section("Group"),
    dcr_seg_input("ctl_active", NULL,
                  stats::setNames(as.character(seq_len(k)), groups),
                  selected = "1", colors = dcr_palette(k),
                  aria_label = "Active group"),
    shiny::textInput("ctl_groups", "Groups (comma-separated)",
                     paste(groups, collapse = ", "), updateOn = "blur"),
    dcr_section("Edit"),
    dcr_seg_input("ctl_target", NULL, c(Curve = "curve", Error = "error"),
                  selected = options$target, aria_label = "Edit target",
                  icons = list(curve = regression_seg_icon(
                    "M2 16 C8 16 9 5 18 4"),
                    error = regression_seg_icon(
                      "M2 12 C8 12 9 4 18 3 L18 10 C9 11 8 19 2 19 Z",
                      fill = TRUE))),
    dcr_section("Mode"),
    dcr_seg_input("ctl_mode", NULL, c(Pull = "pull", Paint = "paint"),
                  selected = options$mode, aria_label = "Brush mode",
                  icons = list(pull = regression_seg_icon(
                    "M10 3 V17 M6.5 6.5 L10 3 L13.5 6.5 M6.5 13.5 L10 17 L13.5 13.5"),
                    paint = regression_seg_icon(
                      "M17 3 L10 10 M10 10 C6.5 9.5 5 12.5 3.5 17 C8 16.5 11 15 10.5 11.5"))),
    shiny::sliderInput("ctl_brush",
                       tags$span("Brush ", tags$span(class = "dcr-kbd", "[ ]")),
                       min = 0.005, max = 1, value = options$brush,
                       step = 0.005, ticks = FALSE),
    tags$details(
      class = "dcr-details",
      tags$summary("Equation"),
      shiny::textInput("ctl_equation", "y =", value = "", updateOn = "blur"),
      tags$div(class = "d-flex flex-wrap gap-1 mb-2",
               example("x"), example("sin(x)"), example("log(x)"),
               example("exp(x/3)"), example("x^2/10")),
      tags$button(type = "button", class = "btn btn-primary btn-sm",
                  `data-dcr-action` = "apply-equation", "Apply")
    ),
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Error shape"),
      tags$div(
        class = "d-flex gap-1 mb-2",
        shape("preset-const", "Constant", "M2 7 H22"),
        shape("preset-cone", "Cone", "M2 6 L22 2 M2 8 L22 12"),
        shape("preset-rcone", "Reverse cone", "M2 2 L22 6 M2 12 L22 8"),
        shape("preset-bowtie", "Bowtie", "M2 2 L12 6 L22 2 M2 12 L12 8 L22 12"),
        shape("preset-bulge", "Bulge", "M2 6 L12 2 L22 6 M2 8 L12 12 L22 8")
      ),
      shiny::sliderInput("ctl_level", "Error level (sd)", min = 0,
                         max = options$level_max, value = options$level,
                         step = 0.01, ticks = FALSE),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "fit-y", "Fit to y")
    ),
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Data"),
      dcr_fields_input("ctl_xlim", "x range", options$xlim, type = "number"),
      shiny::numericInput("ctl_n", "Sample size per group (n)",
                          value = options$n, min = 1, max = 1e6, step = 1),
      shiny::checkboxInput("ctl_shared_x", "Same x for all groups",
                           value = isTRUE(options$shared_x)),
      shiny::checkboxInput("ctl_show", "Show sample", value = FALSE),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "resample", "Resample"),
      dcr_fields_input("ctl_names", "Names", unlist(options$names))
    )
  )
}
