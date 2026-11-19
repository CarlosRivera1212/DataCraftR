# Variable names: 3 to 12 unique, non-empty, trimmed.
radar_variables <- function(x) {
  x <- unlist(x)
  if (!is.character(x)) stop("variables must be a character vector.", call. = FALSE)
  x <- trimws(x)
  if (length(x) < 3L || length(x) > 12L) {
    stop("variables must have 3 to 12 names.", call. = FALSE)
  }
  if (anyNA(x) || any(!nzchar(x))) {
    stop("variables must not contain empty names.", call. = FALSE)
  }
  if (anyDuplicated(x)) stop("variables must be unique.", call. = FALSE)
  x
}

# nrow x ncol numeric matrix (byrow) from a matrix, a list of per-row vectors
# or a flat vector (1 group, or scalars collapsed by JSON). Rejects ragged rows.
radar_matrix <- function(v, what, nrow, ncol, row_what, col_what) {
  if (is.list(v)) {
    rows <- lapply(v, function(r) unlist(r))
    if (length(unique(lengths(rows))) != 1L) {
      stop(what, " must have the same length in every row.", call. = FALSE)
    }
    v <- do.call(rbind, rows)
  }
  if (!is.numeric(v)) stop(what, " must be numeric.", call. = FALSE)
  if (!is.matrix(v)) v <- matrix(v, nrow = nrow, byrow = TRUE)
  if (nrow(v) != nrow) {
    stop(what, " must have one row per ", row_what, ".", call. = FALSE)
  }
  if (ncol(v) != ncol) {
    stop(what, " must have one column per ", col_what, ".", call. = FALSE)
  }
  storage.mode(v) <- "double"
  v
}

#' @export
#' @noRd
spec_from_json.dcr_json_radar <- function(x) {
  groups <- check_names(unlist(x[["groups"]]), "groups")
  k <- length(groups)
  vars <- radar_variables(x[["variables"]])
  p <- length(vars)
  gname <- x[["group_name"]] %||% "group"
  gname <- check_names(unlist(gname), "group_name")
  if (length(gname) != 1L) stop("group_name must be a single name.", call. = FALSE)
  if (gname %in% vars) {
    stop("group_name must differ from every variable name.", call. = FALSE)
  }
  ranges <- radar_matrix(x[["ranges"]], "ranges", p, 2L, "variable", "bound")
  for (j in seq_len(p)) check_range(ranges[j, ], paste0("ranges[", j, "]"))
  mean <- radar_matrix(x[["mean"]], "mean", k, p, "group", "variable")
  sd <- radar_matrix(x[["sd"]], "sd", k, p, "group", "variable")
  if (anyNA(mean) || any(!is.finite(mean))) stop("mean must be finite.", call. = FALSE)
  if (any(mean < rep(ranges[, 1], each = k) | mean > rep(ranges[, 2], each = k))) {
    stop("mean must lie within the range of its variable.", call. = FALSE)
  }
  if (anyNA(sd) || any(!is.finite(sd)) || any(sd < 0)) {
    stop("sd must be finite and non-negative.", call. = FALSE)
  }
  n <- x[["n"]]
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) ||
      n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  if (n * k > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  integers <- x[["integers"]]
  if (is.null(integers)) integers <- FALSE
  integers <- unlist(integers)
  if (!is.logical(integers) || length(integers) != 1L || is.na(integers)) {
    stop("integers must be TRUE or FALSE.", call. = FALSE)
  }
  new_dcr_spec("radar", groups = groups, variables = vars, ranges = ranges,
               mean = mean, sd = sd, n = n, integers = integers,
               group_name = gname, seed = x[["seed"]])
}

# Truncated normal on [a, b] by inverse CDF, exact (no rejection). Works in
# log space on the side of the distribution with the smaller tail so that
# means far outside the range still behave.
rtnorm_range <- function(n, mean, sd, a, b) {
  if (sd == 0) return(rep(mean, n))
  za <- (a - mean) / sd
  zb <- (b - mean) / sd
  flip <- za + zb > 0
  if (flip) {
    t <- za
    za <- -zb
    zb <- -t
  }
  lpa <- stats::pnorm(za, log.p = TRUE)
  lpb <- stats::pnorm(zb, log.p = TRUE)
  w <- exp(lpa - lpb)
  u <- stats::runif(n)
  lp <- lpb + log(w + u * (1 - w))
  z <- stats::qnorm(lp, log.p = TRUE)
  z <- pmin(pmax(z, za), zb)
  x <- if (flip) mean - sd * z else mean + sd * z
  pmin(pmax(x, a), b)
}

# Exact mean and sd of a normal(mean, sd) truncated to [a, b].
tnorm_moments <- function(mean, sd, a, b) {
  if (sd == 0) return(c(mean = mean, sd = 0))
  za <- (a - mean) / sd
  zb <- (b - mean) / sd
  flip <- za + zb > 0
  if (flip) {
    t <- za
    za <- -zb
    zb <- -t
  }
  lpa <- stats::pnorm(za, log.p = TRUE)
  lpb <- stats::pnorm(zb, log.p = TRUE)
  lz <- lpb + log1p(-exp(lpa - lpb))
  ra <- exp(stats::dnorm(za, log = TRUE) - lz)
  rb <- exp(stats::dnorm(zb, log = TRUE) - lz)
  m <- ra - rb
  v <- 1 + za * ra - zb * rb - m^2
  if (!is.finite(m) || !is.finite(v)) {
    # Degenerate (mass piled at the nearest bound).
    m <- zb
    v <- 0
  }
  m <- min(max(m, za), zb)
  s <- min(sqrt(max(v, 0)), (zb - za) / 2)
  c(mean = if (flip) mean - sd * m else mean + sd * m, sd = sd * s)
}

#' @export
#' @noRd
sample_spec.dcr_spec_radar <- function(spec, n) {
  k <- length(spec$groups)
  p <- length(spec$variables)
  cols <- lapply(seq_len(p), function(j) {
    a <- spec$ranges[j, 1]
    b <- spec$ranges[j, 2]
    v <- unlist(lapply(seq_len(k), function(i) {
      rtnorm_range(n, spec$mean[i, j], spec$sd[i, j], a, b)
    }))
    if (isTRUE(spec$integers)) v <- pmin(pmax(round(v), a), b)
    v
  })
  grp <- structure(rep(seq_len(k), each = n), levels = spec$groups,
                   class = "factor")
  df <- data.frame(grp, cols, check.names = FALSE)
  names(df) <- c(spec$group_name, spec$variables)
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_radar <- function(spec) {
  k <- length(spec$groups)
  p <- length(spec$variables)
  out <- data.frame(group = rep(spec$groups, each = p),
                    variable = rep(spec$variables, times = k),
                    mean = NA_real_, sd = NA_real_, stringsAsFactors = FALSE)
  r <- 0L
  for (i in seq_len(k)) {
    for (j in seq_len(p)) {
      r <- r + 1L
      m <- tnorm_moments(spec$mean[i, j], spec$sd[i, j],
                         spec$ranges[j, 1], spec$ranges[j, 2])
      out$mean[r] <- m[["mean"]]
      out$sd[r] <- m[["sd"]]
    }
  }
  out
}

#' @export
#' @noRd
spec_n.dcr_spec_radar <- function(spec) spec$n * length(spec$groups)

#' @export
#' @noRd
spec_is_empty.dcr_spec_radar <- function(spec) FALSE

#' @export
#' @noRd
spec_kind.dcr_spec_radar <- function(spec) "population"
