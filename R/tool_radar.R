# Radar tool: initial profiles, sidebar, control validation and the public
# entry points. The drawing itself lives in inst/www/dcr/tools/radar.js.
#
# The per-variable ranges travel as ONE input, `ctl_ranges`: a container of
# 2p number fields (min, max per variable, in order) read by the generic
# fields binding as a flat array. R validates every pair and forwards a list
# of pairs; JS rebuilds the fields when the variable list changes.

# Initial profile (deterministic, mirrored by DCR.tools.radar.initial in JS):
# group k, variable j of p sits at mid + 0.25 * width * cos(angle); sd is 10 %
# of the range. `ranges` is a p x 2 matrix. Returns list(mean, sd), k x p.
radar_initial <- function(groups, ranges) {
  k <- length(groups)
  p <- nrow(ranges)
  mid <- (ranges[, 1] + ranges[, 2]) / 2
  width <- ranges[, 2] - ranges[, 1]
  mean <- matrix(0, k, p)
  for (i in seq_len(k)) {
    j <- seq_len(p)
    ang <- 2 * pi * (j - 1) / p + 2 * pi * (i - 1) / max(2, k)
    mean[i, ] <- mid + 0.25 * width * cos(ang)
  }
  list(mean = mean, sd = matrix(0.1 * width, k, p, byrow = TRUE))
}

# Validate the arguments of dcr_radar() and build the tool options.
radar_options <- function(variables, groups, n, range, integers, group_name) {
  vars <- radar_variables(variables)
  p <- length(vars)
  groups <- check_names(groups, "groups")
  k <- length(groups)
  gname <- check_names(group_name, "group_name")
  if (length(gname) != 1L) stop("group_name must be a single name.", call. = FALSE)
  if (gname %in% vars) {
    stop("group_name must differ from every variable name.", call. = FALSE)
  }
  n <- histogram_check_n(n)
  if (n * k > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  if (!is.logical(integers) || length(integers) != 1L || is.na(integers)) {
    stop("integers must be TRUE or FALSE.", call. = FALSE)
  }
  if (is.list(range)) {
    if (length(range) != p) {
      stop("range must have one pair per variable.", call. = FALSE)
    }
    ranges <- do.call(rbind, lapply(seq_len(p), function(j) {
      as.numeric(check_range(unlist(range[[j]]), paste0("range[", j, "]")))
    }))
  } else {
    r <- as.numeric(check_range(range, "range"))
    ranges <- matrix(r, nrow = p, ncol = 2L, byrow = TRUE)
  }
  init <- radar_initial(groups, ranges)
  list(groups = groups, variables = vars, ranges = ranges, mean = init$mean,
       sd = init$sd, n = n, integers = integers, group_name = gname)
}

#' Draw group profiles on a radar chart and get a random sample
#'
#' Opens the Radar gadget. Each group is a profile on a radar chart: drag a
#' vertex along its spoke to set the mean of a variable and a band handle to
#' set its standard deviation, then press **Done** to get a random sample of
#' size `n` per group. Values are normal, truncated to each variable's range.
#'
#' @param variables Variable names (3 to 12, unique, non-empty).
#' @param groups Initial group names (1 to 10, unique, non-empty).
#' @param n Sample size per group, a whole number from 1 to 1e6 (with `n`
#'   times the number of groups at most 1e6).
#' @param range Initial range of every variable: two finite numbers,
#'   increasing, or a list with one such pair per variable.
#' @param integers If `TRUE`, values are rounded to whole numbers.
#' @param group_name Name of the group column; it must differ from the
#'   variable names.
#' @return A data.frame with a group factor (levels are the groups) and one
#'   numeric column per variable, carrying its spec (see [dcr_spec()]);
#'   `NULL` invisibly on Cancel.
#' @examples
#' if (interactive()) {
#'   df <- dcr_radar(c("speed", "power", "agility"), groups = c("A", "B"))
#' }
#' @export
dcr_radar <- function(variables = c("V1", "V2", "V3", "V4", "V5"),
                      groups = c("A", "B"), n = 50, range = c(0, 10),
                      integers = FALSE, group_name = "group") {
  opts <- radar_options(variables, groups, n, range, integers, group_name)
  run_dcr_gadget(radar_tool(opts), "console")
}

#' Radar addin: draw, save the spec and insert code
#' @keywords internal
#' @export
dcr_radar_addin <- function() {
  run_dcr_gadget(radar_tool(), "addin")
  invisible()
}

# Default options (also used by the addin).
radar_defaults <- function() {
  vars <- paste0("V", 1:5)
  groups <- c("A", "B")
  ranges <- matrix(c(0, 10), nrow = 5L, ncol = 2L, byrow = TRUE)
  init <- radar_initial(groups, ranges)
  list(groups = groups, variables = vars, ranges = ranges, mean = init$mean,
       sd = init$sd, n = 50, integers = FALSE, group_name = "group",
       target = "mean")
}

#' @noRd
radar_tool <- function(options = list()) {
  new_dcr_tool(
    "radar", title = "Radar profiles", sidebar = radar_sidebar,
    controls = c("groups", "active", "target", "variables", "ranges", "n",
                 "integers", "group_name"),
    options = utils::modifyList(radar_defaults(), options),
    validate = radar_validate
  )
}

# Comma-separated text (or a vector) as a trimmed character vector.
radar_split <- function(value) {
  txt <- paste(as.character(unlist(value)), collapse = ",")
  trimws(strsplit(txt, ",", fixed = TRUE)[[1]])
}

radar_validate <- function(key, value, ctl = list(), ...) {
  switch(
    key,
    groups = check_names(radar_split(value), "groups"),
    variables = radar_variables(radar_split(value)),
    n = histogram_check_n(unlist(value)),
    group_name = {
      g <- check_names(radar_split(value), "group_name")
      if (length(g) != 1L) {
        stop("group_name must be a single name.", call. = FALSE)
      }
      vars <- tryCatch(radar_split(ctl$variables), error = function(e) character())
      if (g %in% vars) {
        stop("group_name must differ from every variable name.", call. = FALSE)
      }
      g
    },
    ranges = {
      # Blank number fields arrive as NULL; keep them as NA so the pairs stay
      # aligned and the range check names the offender.
      v <- vapply(as.list(value), function(x) {
        if (is.null(x) || length(x) != 1L) return(NA_real_)
        suppressWarnings(as.numeric(x))
      }, numeric(1))
      if (length(v) %% 2L != 0L || length(v) < 6L || length(v) > 24L) {
        stop("ranges must be one min/max pair per variable (3 to 12 pairs).",
             call. = FALSE)
      }
      if (anyNA(v)) stop("ranges must be numeric.", call. = FALSE)
      m <- matrix(v, ncol = 2L, byrow = TRUE)
      lapply(seq_len(nrow(m)), function(j) {
        as.numeric(check_range(m[j, ], paste0("ranges[", j, "]")))
      })
    },
    value
  )
}

# 20 x 20 glyph for the segmented controls and presets.
radar_icon <- function(d, fill = FALSE) {
  tags <- htmltools::tags
  tags$svg(
    xmlns = "http://www.w3.org/2000/svg", viewBox = "0 0 20 20", width = "20",
    height = "20", `aria-hidden` = "true", focusable = "false", fill = "none",
    stroke = "currentColor", `stroke-width` = "1.5", `stroke-linecap` = "round",
    `stroke-linejoin` = "round",
    tags$path(d = d, fill = if (fill) "currentColor", `fill-opacity` = if (fill) "0.15")
  )
}

# The min/max fields of every variable in one `ctl_ranges` container.
radar_ranges_input <- function(variables, ranges) {
  tags <- htmltools::tags
  rows <- lapply(seq_along(variables), function(j) {
    tags$div(
      class = "dcr-range-row",
      tags$span(class = "dcr-range-name", variables[[j]]),
      tags$input(type = "number", class = "form-control", value = ranges[j, 1],
                 step = "any", `aria-label` = paste(variables[[j]], "min")),
      tags$input(type = "number", class = "form-control", value = ranges[j, 2],
                 step = "any", `aria-label` = paste(variables[[j]], "max"))
    )
  })
  tags$div(
    class = "form-group shiny-input-container",
    tags$div(id = "ctl_ranges", class = "dcr-ranges dcr-fields-input", rows)
  )
}

radar_sidebar <- function(options) {
  tags <- htmltools::tags
  groups <- options$groups
  k <- length(groups)
  ranges <- options$ranges
  preset <- function(action, label, d) {
    tags$button(type = "button", class = "btn btn-light btn-sm dcr-shape",
                `data-dcr-action` = action, title = label,
                `aria-label` = label, radar_icon(d))
  }
  htmltools::tagList(
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Groups"),
      dcr_seg_input("ctl_active", NULL,
                    stats::setNames(as.character(seq_len(k)), groups),
                    selected = "1", colors = dcr_palette(k),
                    aria_label = "Active group"),
      shiny::textInput("ctl_groups", "Groups (comma-separated)",
                       paste(groups, collapse = ", "), updateOn = "blur")
    ),
    dcr_section("Edit"),
    dcr_seg_input("ctl_target", NULL, c(Mean = "mean", Spread = "spread"),
                  selected = options$target, aria_label = "Edit target",
                  icons = list(
                    mean = radar_icon("M10 2 L17 7 L14.5 16 L5.5 16 L3 7 Z",
                                      fill = TRUE),
                    spread = radar_icon(
                      "M10 1.5 L18 7 L15 17 L5 17 L2 7 Z M10 6 L13.5 8.5 L12.2 13 L7.8 13 L6.5 8.5 Z"))),
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Variables"),
      shiny::textInput("ctl_variables", "Variables (comma-separated)",
                       paste(options$variables, collapse = ", "),
                       updateOn = "blur"),
      radar_ranges_input(options$variables, ranges)
    ),
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Spread"),
      tags$div(
        class = "d-flex gap-1 mb-2",
        preset("preset-tight", "Tight (5 %)", "M10 3 V17 M7 6 L10 3 L13 6 M7 14 L10 17 L13 14"),
        preset("preset-medium", "Medium (10 %)", "M10 2 V18 M6 6 L10 2 L14 6 M6 14 L10 18 L14 14"),
        preset("preset-wide", "Wide (20 %)", "M10 1 V19 M5 6 L10 1 L15 6 M5 14 L10 19 L15 14 M4 10 H16")
      ),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "same-all", "Same for all groups")
    ),
    tags$details(
      class = "dcr-details", open = NA,
      tags$summary("Data"),
      shiny::numericInput("ctl_n", "Sample size per group (n)",
                          value = options$n, min = 1, max = 1e6, step = 1),
      shiny::checkboxInput("ctl_integers", "Integers",
                           value = isTRUE(options$integers)),
      shiny::checkboxInput("ctl_show", "Show sample", value = FALSE),
      tags$button(type = "button", class = "btn btn-light btn-sm",
                  `data-dcr-action` = "resample", "Resample"),
      shiny::textInput("ctl_group_name", "Group column name",
                       options$group_name, updateOn = "blur")
    )
  )
}
