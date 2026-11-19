#' @export
#' @noRd
spec_from_json.dcr_json_scatter <- function(x) {
  nm <- x[["names"]] %||% list(x = "x", y = "y", group = "group")
  nms <- check_names(c(nm[["x"]], nm[["y"]], nm[["group"]]), "names")
  if (length(nms) != 3L) stop("names must have x, y and group.", call. = FALSE)
  groups <- check_names(x[["groups"]], "groups")
  xlim <- check_range(x[["xlim"]], "xlim")
  ylim <- check_range(x[["ylim"]], "ylim")

  pts <- x[["points"]]
  px <- unlist(pts[["x"]])
  py <- unlist(pts[["y"]])
  pg <- unlist(pts[["group"]])
  if (is.null(px)) px <- numeric(0)
  if (is.null(py)) py <- numeric(0)
  if (is.null(pg)) pg <- character(0)
  if (length(px) != length(py) || length(px) != length(pg)) {
    stop("points x, y and group must have the same length.", call. = FALSE)
  }
  if (!is.numeric(px) || !is.numeric(py) || anyNA(px) || anyNA(py) ||
      any(!is.finite(px)) || any(!is.finite(py))) {
    stop("points x and y must be finite numbers.", call. = FALSE)
  }
  pg <- as.character(pg)
  if (anyNA(pg) || !all(pg %in% groups)) {
    stop("points contain a group not listed in groups.", call. = FALSE)
  }
  o <- order(match(pg, groups), seq_along(pg))
  new_dcr_spec("scatter", names = stats::setNames(as.list(nms), c("x", "y", "group")),
               groups = groups, xlim = as.numeric(xlim), ylim = as.numeric(ylim),
               points = list(x = as.numeric(px[o]), y = as.numeric(py[o]),
                             group = pg[o]),
               n = NULL, seed = NULL)
}

#' @export
#' @noRd
sample_spec.dcr_spec_scatter <- function(spec, n) {
  p <- spec$points
  df <- data.frame(p$x, p$y,
                   factor(p$group, levels = spec$groups))
  names(df) <- unlist(spec$names, use.names = FALSE)
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_scatter <- function(spec) {
  p <- spec$points
  g <- factor(p$group, levels = spec$groups)
  safe_sd <- function(v) if (length(v) >= 2L) stats::sd(v) else NA_real_
  safe_r <- function(a, b) {
    if (length(a) >= 2L && stats::sd(a) > 0 && stats::sd(b) > 0) {
      stats::cor(a, b)
    } else {
      NA_real_
    }
  }
  row <- function(label, a, b) {
    data.frame(group = label, n = length(a),
               mean_x = if (length(a)) mean(a) else NA_real_,
               mean_y = if (length(a)) mean(b) else NA_real_,
               sd_x = safe_sd(a), sd_y = safe_sd(b), r = safe_r(a, b),
               stringsAsFactors = FALSE)
  }
  rows <- lapply(spec$groups, function(lv) {
    i <- which(g == lv)
    row(lv, p$x[i], p$y[i])
  })
  # last row: all points together (global correlation)
  do.call(rbind, c(rows, list(row("All", p$x, p$y))))
}

#' @export
#' @noRd
spec_n.dcr_spec_scatter <- function(spec) length(spec$points$x)

#' @export
#' @noRd
spec_is_empty.dcr_spec_scatter <- function(spec) length(spec$points$x) == 0L

#' @export
#' @noRd
spec_kind.dcr_spec_scatter <- function(spec) "literal"
