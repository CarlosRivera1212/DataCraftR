#' @export
#' @noRd
spec_from_json.dcr_json_density <- function(x) {
  variables <- check_names(x[["variables"]], "variables")
  xlim <- check_range(x[["xlim"]], "xlim")
  n <- x[["n"]]
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) ||
      n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  y <- x[["curves"]]
  if (!is.numeric(y)) stop("curves must be numeric.", call. = FALSE)
  if (!is.matrix(y)) y <- matrix(y, nrow = length(variables))
  if (nrow(y) != length(variables)) {
    stop("curves must have one row per variable.", call. = FALSE)
  }
  if (ncol(y) < 3L || ncol(y) > 1001L) {
    stop("curves must have between 3 and 1001 grid points per variable.",
         call. = FALSE)
  }
  if (anyNA(y) || any(!is.finite(y)) || any(y < 0)) {
    stop("curves must be finite and non-negative.", call. = FALSE)
  }
  if (any(y[, 1L] != 0) || any(y[, ncol(y)] != 0)) {
    stop("curves must be 0 at both ends.", call. = FALSE)
  }
  storage.mode(y) <- "double"
  new_dcr_spec("density", variables = variables, xlim = as.numeric(xlim),
               curves = y, n = n, seed = x[["seed"]])
}

# Cell geometry of a piecewise-linear density on an equally spaced grid.
density_grid <- function(xlim, K) {
  xs <- seq(xlim[1], xlim[2], length.out = K)
  list(xs = xs, h = (xlim[2] - xlim[1]) / (K - 1L))
}

# Offset s in [0, h] inside a cell where the cumulative mass is r, for a
# density running linearly from a to b over width h. Stable form of the
# quadratic root: s = 2r / (a + sqrt(a^2 + 4 A r)), A = (b - a) / (2h).
density_cell_offset <- function(r, a, b, h) {
  A <- (b - a) / (2 * h)
  den <- a + sqrt(pmax(0, a^2 + 4 * A * r))
  s <- ifelse(den > 0, 2 * r / den, 0)
  pmin(h, pmax(0, s))
}

# Quantiles of the piecewise-linear density through the points (xs, ys),
# vectorised over the probabilities u.
qdensity_pl <- function(u, xs, ys) {
  K <- length(xs)
  h <- (xs[K] - xs[1L]) / (K - 1L)
  m <- (ys[-K] + ys[-1L]) / 2 * h
  cum <- cumsum(m)
  total <- cum[K - 1L]
  target <- u * total
  # First cell whose end mass exceeds the target (skips empty cells); a target
  # at or past the total mass falls back to the last non-empty cell.
  i <- pmin(K - 1L, findInterval(target, cum) + 1L)
  i <- ifelse(m[i] > 0, i, max(which(m > 0)))
  prev <- c(0, cum)[i]
  r <- pmin(m[i], pmax(0, target - prev))
  xs[i] + density_cell_offset(r, ys[i], ys[i + 1L], h)
}

#' @export
#' @noRd
sample_spec.dcr_spec_density <- function(spec, n) {
  K <- ncol(spec$curves)
  g <- density_grid(spec$xlim, K)
  keep <- rowSums(spec$curves) > 0
  cols <- lapply(which(keep), function(v) {
    y <- spec$curves[v, ]
    m <- (y[-K] + y[-1L]) / 2 * g$h
    i <- sample.int(K - 1L, n, replace = TRUE, prob = m)
    r <- stats::runif(n) * m[i]
    g$xs[i] + density_cell_offset(r, y[i], y[i + 1L], g$h)
  })
  names(cols) <- spec$variables[keep]
  df <- as.data.frame(cols, check.names = FALSE, optional = TRUE)
  if (!all(keep)) attr(df, "dropped") <- spec$variables[!keep]
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_density <- function(spec) {
  K <- ncol(spec$curves)
  g <- density_grid(spec$xlim, K)
  h <- g$h
  x0 <- g$xs[-K]
  rows <- lapply(seq_along(spec$variables), function(v) {
    y <- spec$curves[v, ]
    a <- y[-K]
    b <- y[-1L]
    m <- (a + b) / 2 * h
    total <- sum(m)
    if (total <= 0) return(c(NA_real_, NA_real_, NA_real_))
    # Per cell, with t = x - x0 in [0, h] and f linear from a to b:
    #   int t f dt   = h^2 (a/6 + b/3)
    #   int t^2 f dt = h^3 (a/12 + b/4)
    i1 <- h^2 * (a / 6 + b / 3)
    i2 <- h^3 * (a / 12 + b / 4)
    ex <- sum(x0 * m + i1) / total
    ex2 <- sum(x0^2 * m + 2 * x0 * i1 + i2) / total
    c(ex, sqrt(max(ex2 - ex^2, 0)), qdensity_pl(0.5, g$xs, y))
  })
  r <- do.call(rbind, rows)
  data.frame(variable = spec$variables, mean = r[, 1], sd = r[, 2],
             median = r[, 3], stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_density <- function(spec) spec$n

#' @export
#' @noRd
spec_is_empty.dcr_spec_density <- function(spec) all(spec$curves == 0)

#' @export
#' @noRd
spec_kind.dcr_spec_density <- function(spec) "population"
