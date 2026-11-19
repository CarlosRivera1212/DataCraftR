# col, row names as a named list in that order, validated.
mosaic_names <- function(names) {
  keys <- c("col", "row")
  if (!is.null(names(names)) && setequal(names(names), keys)) {
    names <- names[keys]
  }
  if (length(names) != 2L) {
    stop("names must have col and row.", call. = FALSE)
  }
  nms <- check_names(as.character(unlist(names, use.names = FALSE)), "names")
  stats::setNames(as.list(nms), keys)
}

#' @export
#' @noRd
spec_from_json.dcr_json_mosaic <- function(x) {
  cols <- check_names(x[["cols"]], "cols")
  rows <- check_names(x[["rows"]], "rows")
  if (length(cols) < 2L) stop("cols must have 2 to 10 names.", call. = FALSE)
  if (length(rows) < 2L) stop("rows must have 2 to 10 names.", call. = FALSE)
  names <- mosaic_names(x[["names"]] %||% list(col = "exposure", row = "outcome"))
  nr <- length(rows)
  nc <- length(cols)
  counts <- x[["counts"]]
  if (is.list(counts)) counts <- do.call(rbind, lapply(counts, as.numeric))
  if (!is.numeric(counts) && !is.logical(counts)) {
    stop("counts must be numeric.", call. = FALSE)
  }
  if (is.null(dim(counts))) {
    if (length(counts) != nr * nc) {
      stop("counts dimensions must be rows x cols.", call. = FALSE)
    }
    counts <- matrix(counts, nrow = nr, byrow = TRUE)
  }
  if (!identical(as.integer(dim(counts)), c(nr, nc))) {
    stop("counts dimensions must be rows x cols.", call. = FALSE)
  }
  if (anyNA(counts) || any(!is.finite(counts)) || any(counts < 0) ||
      any(counts != round(counts))) {
    stop("counts must be whole numbers >= 0.", call. = FALSE)
  }
  total <- sum(as.numeric(counts))
  if (total < 1) stop("counts must total at least 1.", call. = FALSE)
  if (total > 1e6) {
    stop("counts must total at most 1e6 observations.", call. = FALSE)
  }
  counts <- matrix(as.integer(counts), nrow = nr, dimnames = list(rows, cols))
  new_dcr_spec("mosaic", cols = cols, rows = rows, names = names,
               counts = counts, n = NULL, seed = NULL)
}

#' @export
#' @noRd
sample_spec.dcr_spec_mosaic <- function(spec, n) {
  nr <- length(spec$rows)
  nc <- length(spec$cols)
  # column-major over (row, col) is already column-then-row order
  idx <- rep(seq_len(nr * nc), times = as.vector(spec$counts))
  r <- (idx - 1L) %% nr + 1L
  k <- (idx - 1L) %/% nr + 1L
  out <- data.frame(factor(spec$cols[k], levels = spec$cols),
                    factor(spec$rows[r], levels = spec$rows))
  names(out) <- c(spec$names$col, spec$names$row)
  out
}

#' @export
#' @noRd
spec_stats.dcr_spec_mosaic <- function(spec) {
  nr <- length(spec$rows)
  nc <- length(spec$cols)
  # Counts with a "Total" row (per column) and a "Total" column (row totals
  # and grand total), in long form: for each column its row cells then its
  # total; then the row totals and the grand total.
  m <- rbind(spec$counts, colSums(spec$counts))
  m <- cbind(m, rowSums(m))
  cols <- c(spec$cols, "Total")
  rows <- c(spec$rows, "Total")
  coltot <- m[nr + 1L, ]
  cnt <- as.vector(m)
  ci <- rep(seq_len(nc + 1L), each = nr + 1L)
  grand <- sum(spec$counts)
  data.frame(col = cols[ci],
             row = rep(rows, times = nc + 1L),
             count = cnt,
             prop = cnt / grand,
             prop_in_col = ifelse(coltot[ci] > 0, cnt / coltot[ci], NA_real_),
             stringsAsFactors = FALSE)
}

#' @export
#' @noRd
spec_n.dcr_spec_mosaic <- function(spec) sum(spec$counts)

#' @export
#' @noRd
spec_is_empty.dcr_spec_mosaic <- function(spec) FALSE

#' @export
#' @noRd
spec_kind.dcr_spec_mosaic <- function(spec) "literal"
