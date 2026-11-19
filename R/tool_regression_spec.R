# x, y, group names as a named list in that order, validated.
regression_names <- function(names) {
  keys <- c("x", "y", "group")
  if (!is.null(names(names)) && setequal(names(names), keys)) {
    names <- names[keys]
  }
  if (length(names) != 3L) {
    stop("names must have x, y and group.", call. = FALSE)
  }
  nms <- check_names(as.character(unlist(names, use.names = FALSE)), "names")
  stats::setNames(as.list(nms), keys)
}

# groups x K numeric matrix from a matrix, a list of per-group vectors or a
# plain vector (one group).
regression_matrix <- function(v, what, k) {
  if (is.list(v)) v <- do.call(rbind, lapply(v, function(r) as.numeric(unlist(r))))
  if (!is.numeric(v)) stop(what, " must be numeric.", call. = FALSE)
  if (!is.matrix(v)) v <- matrix(v, nrow = 1L)
  if (nrow(v) != k) {
    stop(what, " must have one row per group.", call. = FALSE)
  }
  if (ncol(v) < 3L || ncol(v) > 1001L) {
    stop(what, " must have between 3 and 1001 grid points per group.",
         call. = FALSE)
  }
  storage.mode(v) <- "double"
  v
}

#' @export
#' @noRd
spec_from_json.dcr_json_regression <- function(x) {
  nm <- x[["names"]] %||% list(x = "x", y = "y", group = "group")
  nms <- regression_names(nm)
  groups <- check_names(unlist(x[["groups"]]), "groups")
  k <- length(groups)
  xlim <- check_range(unlist(x[["xlim"]]), "xlim")
  f <- regression_matrix(x[["f"]], "f", k)
  s <- regression_matrix(x[["s"]], "s", k)
  if (!identical(dim(f), dim(s))) {
    stop("f and s must have the same dimensions.", call. = FALSE)
  }
  if (anyNA(f) || any(!is.finite(f))) stop("f must be finite.", call. = FALSE)
  if (anyNA(s) || any(!is.finite(s)) || any(s < 0)) {
    stop("s must be finite and non-negative.", call. = FALSE)
  }
  n <- x[["n"]]
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) ||
      n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  if (n * k > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  shared <- x[["shared_x"]]
  if (is.null(shared)) shared <- TRUE
  shared <- unlist(shared)
  if (!is.logical(shared) || length(shared) != 1L || is.na(shared)) {
    stop("shared_x must be TRUE or FALSE.", call. = FALSE)
  }
  new_dcr_spec("regression", groups = groups, names = nms,
               xlim = as.numeric(xlim), f = f, s = s, n = n,
               shared_x = shared, seed = x[["seed"]])
}

#' @export
#' @noRd
sample_spec.dcr_spec_regression <- function(spec, n) {
  k <- length(spec$groups)
  K <- ncol(spec$f)
  xs <- seq(spec$xlim[1], spec$xlim[2], length.out = K)
  xv <- numeric(n * k)
  yv <- numeric(n * k)
  x0 <- if (isTRUE(spec$shared_x)) stats::runif(n, spec$xlim[1], spec$xlim[2])
  for (i in seq_len(k)) {
    xi <- if (is.null(x0)) stats::runif(n, spec$xlim[1], spec$xlim[2]) else x0
    fx <- stats::approx(xs, spec$f[i, ], xout = xi, rule = 2)$y
    sx <- stats::approx(xs, spec$s[i, ], xout = xi, rule = 2)$y
    idx <- (i - 1L) * n + seq_len(n)
    xv[idx] <- xi
    yv[idx] <- fx + sx * stats::rnorm(n)
  }
  grp <- structure(rep(seq_len(k), each = n), levels = spec$groups,
                   class = "factor")
  df <- data.frame(xv, yv, grp, check.names = FALSE)
  names(df) <- unlist(spec$names, use.names = FALSE)
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_regression <- function(spec) {
  K <- ncol(spec$f)
  lo <- spec$xlim[1]
  w <- diff(spec$xlim)
  grid <- seq(lo, spec$xlim[2], length.out = K)
  m <- 20L * (K - 1L)
  xm <- lo + (seq_len(m) - 0.5) / m * w
  mean_x <- lo + w / 2
  sd_x <- w / sqrt(12)
  rows <- lapply(seq_along(spec$groups), function(i) {
    fx <- stats::approx(grid, spec$f[i, ], xout = xm)$y
    sx <- stats::approx(grid, spec$s[i, ], xout = xm)$y
    ef <- mean(fx)
    vf <- mean(fx^2) - ef^2
    es2 <- mean(sx^2)
    cov_xf <- mean(xm * fx) - mean(xm) * ef
    vy <- vf + es2
    degenerate <- !(vy > 1e-12 * max(1, ef^2, es2))
    c(mean_x, sd_x, ef, sqrt(max(vy, 0)),
      if (degenerate) NA_real_ else cov_xf / (sd_x * sqrt(vy)),
      if (degenerate) NA_real_ else max(vf, 0) / vy)
  })
  r <- do.call(rbind, rows)
  data.frame(group = spec$groups, mean_x = r[, 1], sd_x = r[, 2],
             mean_y = r[, 3], sd_y = r[, 4], r = r[, 5], r2_curve = r[, 6],
             stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_regression <- function(spec) spec$n * length(spec$groups)

#' @export
#' @noRd
spec_is_empty.dcr_spec_regression <- function(spec) FALSE

#' @export
#' @noRd
spec_kind.dcr_spec_regression <- function(spec) "population"
