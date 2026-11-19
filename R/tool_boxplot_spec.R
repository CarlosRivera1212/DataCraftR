#' Quantile function of a two-piece distribution with exact quartiles
#' @noRd
qtwopiece <- function(p, q1, q2, q3, family = c("normal", "uniform")) {
  family <- match.arg(family)
  d <- ifelse(p < 0.5, q2 - q1, q3 - q2)
  if (family == "normal") {
    s <- d / stats::qnorm(0.75)
    q2 + s * stats::qnorm(p)
  } else {
    q2 + 4 * d * (p - 0.5)
  }
}

#' @export
#' @noRd
spec_from_json.dcr_json_boxplot <- function(x) {
  family <- x[["family"]]
  if (!is.character(family) || length(family) != 1L ||
      !family %in% c("normal", "uniform")) {
    stop("family must be \"normal\" or \"uniform\".", call. = FALSE)
  }
  variables <- check_names(x[["variables"]], "variables")
  k <- length(variables)
  q <- lapply(c("q1", "q2", "q3"), function(nm) {
    v <- x[[nm]]
    if (!is.numeric(v) || length(v) != k || any(!is.finite(v))) {
      stop(nm, " must be ", k, " finite numbers, one per variable.", call. = FALSE)
    }
    as.numeric(v)
  })
  if (any(!(q[[1]] < q[[2]] & q[[2]] < q[[3]]))) {
    stop("Quartiles must satisfy q1 < q2 < q3 for every variable.", call. = FALSE)
  }
  ylim <- check_range(x[["ylim"]], "ylim")
  new_dcr_spec("boxplot", family = family, variables = variables,
               q1 = q[[1]], q2 = q[[2]], q3 = q[[3]], ylim = as.numeric(ylim),
               n = x[["n"]], seed = x[["seed"]])
}

#' @export
#' @noRd
sample_spec.dcr_spec_boxplot <- function(spec, n) {
  cols <- lapply(seq_along(spec$variables), function(i) {
    qtwopiece(stats::runif(n), spec$q1[i], spec$q2[i], spec$q3[i], spec$family)
  })
  names(cols) <- spec$variables
  as.data.frame(cols, check.names = FALSE, optional = TRUE)
}

#' @export
#' @noRd
spec_stats.dcr_spec_boxplot <- function(spec) {
  dl <- spec$q2 - spec$q1
  du <- spec$q3 - spec$q2
  if (spec$family == "normal") {
    sl <- dl / stats::qnorm(0.75)
    su <- du / stats::qnorm(0.75)
    mean <- spec$q2 + (su - sl) / sqrt(2 * pi)
    sd <- sqrt((sl^2 + su^2) / 2 - (mean - spec$q2)^2)
  } else {
    mean <- spec$q2 + (du - dl) / 2
    sd <- sqrt(2 * (dl^2 + du^2) / 3 - (mean - spec$q2)^2)
  }
  data.frame(variable = spec$variables, q1 = spec$q1, median = spec$q2,
             q3 = spec$q3, iqr = spec$q3 - spec$q1, mean = mean, sd = sd,
             stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_boxplot <- function(spec) spec$n

#' @export
#' @noRd
spec_is_empty.dcr_spec_boxplot <- function(spec) FALSE

#' @export
#' @noRd
spec_kind.dcr_spec_boxplot <- function(spec) "population"
