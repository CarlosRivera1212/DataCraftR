# Per-group numeric parameter vector: finite, one value per group.
bivariate_param <- function(v, what, k) {
  v <- unlist(v)
  if (!is.numeric(v) || length(v) != k || anyNA(v) || any(!is.finite(v))) {
    stop(what, " must be ", k, " finite number(s), one per group.", call. = FALSE)
  }
  as.numeric(v)
}

#' @export
#' @noRd
spec_from_json.dcr_json_bivariate <- function(x) {
  nm <- x[["names"]] %||% list(x = "x", y = "y", group = "group")
  nms <- check_names(c(nm[["x"]], nm[["y"]], nm[["group"]]), "names")
  if (length(nms) != 3L) stop("names must have x, y and group.", call. = FALSE)
  groups <- check_names(unlist(x[["groups"]]), "groups")
  k <- length(groups)
  xlim <- check_range(unlist(x[["xlim"]]), "xlim")
  ylim <- check_range(unlist(x[["ylim"]]), "ylim")
  mean_x <- bivariate_param(x[["mean_x"]], "mean_x", k)
  mean_y <- bivariate_param(x[["mean_y"]], "mean_y", k)
  sd_x <- bivariate_param(x[["sd_x"]], "sd_x", k)
  sd_y <- bivariate_param(x[["sd_y"]], "sd_y", k)
  rho <- bivariate_param(x[["rho"]], "rho", k)
  if (any(sd_x <= 0) || any(sd_y <= 0)) {
    stop("sd_x and sd_y must be greater than 0.", call. = FALSE)
  }
  if (any(abs(rho) >= 1)) stop("rho must be strictly between -1 and 1.", call. = FALSE)
  n <- x[["n"]]
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) ||
      n != round(n) || n < 1 || n > 1e6) {
    stop("n must be a whole number from 1 to 1e6.", call. = FALSE)
  }
  if (n * k > 1e6) {
    stop("n times the number of groups must be at most 1e6.", call. = FALSE)
  }
  new_dcr_spec("bivariate", groups = groups,
               names = stats::setNames(as.list(nms), c("x", "y", "group")),
               xlim = as.numeric(xlim), ylim = as.numeric(ylim),
               mean_x = mean_x, mean_y = mean_y, sd_x = sd_x, sd_y = sd_y,
               rho = rho, n = n, seed = x[["seed"]])
}

#' @export
#' @noRd
sample_spec.dcr_spec_bivariate <- function(spec, n) {
  k <- length(spec$groups)
  xs <- numeric(n * k)
  ys <- numeric(n * k)
  for (i in seq_len(k)) {
    z1 <- stats::rnorm(n)
    z2 <- stats::rnorm(n)
    r <- spec$rho[i]
    idx <- (i - 1L) * n + seq_len(n)
    xs[idx] <- spec$mean_x[i] + spec$sd_x[i] * z1
    ys[idx] <- spec$mean_y[i] + spec$sd_y[i] * (r * z1 + sqrt(1 - r^2) * z2)
  }
  grp <- structure(rep(seq_len(k), each = n), levels = spec$groups,
                   class = "factor")
  df <- data.frame(xs, ys, grp, check.names = FALSE)
  names(df) <- unlist(spec$names, use.names = FALSE)
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_bivariate <- function(spec) {
  mx <- spec$mean_x
  my <- spec$mean_y
  sx <- spec$sd_x
  sy <- spec$sd_y
  rho <- spec$rho
  Mx <- mean(mx)
  My <- mean(my)
  Vx <- mean(sx^2 + mx^2) - Mx^2
  Vy <- mean(sy^2 + my^2) - My^2
  C <- mean(rho * sx * sy + mx * my) - Mx * My
  data.frame(group = c(spec$groups, "All"),
             mean_x = c(mx, Mx), mean_y = c(my, My),
             sd_x = c(sx, sqrt(Vx)), sd_y = c(sy, sqrt(Vy)),
             r = c(rho, C / sqrt(Vx * Vy)),
             stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_bivariate <- function(spec) spec$n * length(spec$groups)

#' @export
#' @noRd
spec_is_empty.dcr_spec_bivariate <- function(spec) FALSE

#' @export
#' @noRd
spec_kind.dcr_spec_bivariate <- function(spec) "population"
