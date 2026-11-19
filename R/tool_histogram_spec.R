#' @export
#' @noRd
spec_from_json.dcr_json_histogram <- function(x) {
  variables <- check_names(x[["variables"]], "variables")
  xlim <- check_range(x[["xlim"]], "xlim")
  nbins <- x[["nbins"]]
  if (!is.numeric(nbins) || length(nbins) != 1L || !is.finite(nbins) ||
      nbins != round(nbins) || nbins < 1 || nbins > 100) {
    stop("nbins must be a whole number from 1 to 100.", call. = FALSE)
  }
  nbins <- as.integer(nbins)
  w <- x[["weights"]]
  if (!is.numeric(w)) stop("weights must be numeric.", call. = FALSE)
  if (!is.matrix(w)) w <- matrix(w, nrow = length(variables))
  if (nrow(w) != length(variables) || ncol(w) != nbins) {
    stop("weights must have one row per variable and one column per bin.",
         call. = FALSE)
  }
  if (anyNA(w) || any(!is.finite(w)) || any(w < 0)) {
    stop("weights must be finite and non-negative.", call. = FALSE)
  }
  storage.mode(w) <- "double"
  new_dcr_spec("histogram", variables = variables, xlim = as.numeric(xlim),
               nbins = nbins, weights = w, n = x[["n"]], seed = x[["seed"]])
}

#' @export
#' @noRd
sample_spec.dcr_spec_histogram <- function(spec, n) {
  width <- (spec$xlim[2] - spec$xlim[1]) / spec$nbins
  keep <- rowSums(spec$weights) > 0
  cols <- lapply(which(keep), function(i) {
    bin <- sample.int(spec$nbins, n, replace = TRUE, prob = spec$weights[i, ])
    spec$xlim[1] + (bin - 1L) * width + stats::runif(n) * width
  })
  names(cols) <- spec$variables[keep]
  df <- as.data.frame(cols, check.names = FALSE, optional = TRUE)
  if (!all(keep)) attr(df, "dropped") <- spec$variables[!keep]
  df
}

#' @export
#' @noRd
spec_stats.dcr_spec_histogram <- function(spec) {
  width <- (spec$xlim[2] - spec$xlim[1]) / spec$nbins
  lo <- spec$xlim[1] + (seq_len(spec$nbins) - 1L) * width
  mid <- lo + width / 2
  rows <- lapply(seq_along(spec$variables), function(i) {
    w <- spec$weights[i, ]
    tot <- sum(w)
    if (tot <= 0) return(c(NA_real_, NA_real_, NA_real_))
    m <- sum(w * mid) / tot
    v <- sum(w * (mid^2 + width^2 / 12)) / tot - m^2
    p <- w / tot
    cp <- cumsum(p)
    k <- which(cp >= 0.5 - 1e-12)[1]
    prev <- if (k > 1L) cp[k - 1L] else 0
    med <- lo[k] + (0.5 - prev) / p[k] * width
    c(m, sqrt(max(v, 0)), med)
  })
  r <- do.call(rbind, rows)
  data.frame(variable = spec$variables, mean = r[, 1], sd = r[, 2],
             median = r[, 3], stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_histogram <- function(spec) spec$n

#' @export
#' @noRd
spec_is_empty.dcr_spec_histogram <- function(spec) all(spec$weights == 0)

#' @export
#' @noRd
spec_kind.dcr_spec_histogram <- function(spec) "population"
