#' @export
#' @noRd
spec_from_json.dcr_json_count <- function(x) {
  variables <- check_names(x[["variables"]], "variables")
  categories <- check_names(x[["categories"]], "categories")
  nv <- length(variables)
  nc <- length(categories)
  counts <- x[["counts"]]
  if (is.list(counts)) counts <- do.call(rbind, lapply(counts, as.numeric))
  if (!is.numeric(counts) && !is.logical(counts)) {
    stop("counts must be numeric.", call. = FALSE)
  }
  if (is.null(dim(counts))) {
    if (length(counts) != nv * nc) {
      stop("counts dimensions must be variables x categories.", call. = FALSE)
    }
    counts <- matrix(counts, nrow = nv)
  }
  if (!identical(dim(counts), c(nv, nc))) {
    stop("counts dimensions must be variables x categories.", call. = FALSE)
  }
  if (anyNA(counts) || any(!is.finite(counts)) || any(counts < 0) ||
      any(counts != round(counts))) {
    stop("counts must be whole numbers >= 0.", call. = FALSE)
  }
  if (sum(counts) > 1e6) {
    stop("counts must total at most 1e6 observations.", call. = FALSE)
  }
  counts <- matrix(as.integer(counts), nrow = nv,
                   dimnames = list(variables, categories))
  new_dcr_spec("count", variables = variables, categories = categories,
               counts = counts, n = NULL, seed = NULL)
}

#' @export
#' @noRd
sample_spec.dcr_spec_count <- function(spec, n) {
  nv <- length(spec$variables)
  nc <- length(spec$categories)
  # column-major over (variable, category); reorder to variable-major
  idx <- rep(seq_len(nv * nc), times = as.vector(spec$counts))
  v <- (idx - 1L) %% nv + 1L
  k <- (idx - 1L) %/% nv + 1L
  o <- order(v, k)
  data.frame(variable = factor(spec$variables[v[o]], levels = spec$variables),
             category = factor(spec$categories[k[o]], levels = spec$categories))
}

#' @export
#' @noRd
spec_stats.dcr_spec_count <- function(spec) {
  nv <- length(spec$variables)
  nc <- length(spec$categories)
  # The counts with a "Total" column (per variable) and a "Total" row (per
  # category, and the grand total), in long form: for each variable its
  # categories then its total; then the category totals and the grand total.
  m <- rbind(cbind(spec$counts, rowSums(spec$counts)),
             c(colSums(spec$counts), sum(spec$counts)))
  vars <- c(spec$variables, "Total")
  cats <- c(spec$categories, "Total")
  tot <- m[, nc + 1L]
  cnt <- as.vector(t(m))
  vi <- rep(seq_len(nv + 1L), each = nc + 1L)
  grand <- sum(spec$counts)
  data.frame(variable = vars[vi],
             category = rep(cats, times = nv + 1L),
             count = cnt,
             prop_in_variable = ifelse(tot[vi] > 0, cnt / tot[vi], NA_real_),
             prop_of_total = if (grand > 0) cnt / grand else NA_real_,
             stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_count <- function(spec) sum(spec$counts)

#' @export
#' @noRd
spec_is_empty.dcr_spec_count <- function(spec) sum(spec$counts) == 0L

#' @export
#' @noRd
spec_kind.dcr_spec_count <- function(spec) "literal"
