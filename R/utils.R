#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a

#' Validate a vector of group/variable/category names
#' @noRd
check_names <- function(x, what) {
  if (!is.character(x)) stop(what, " must be a character vector.", call. = FALSE)
  x <- trimws(x)
  if (length(x) < 1L || length(x) > 10L) {
    stop(what, " must have 1 to 10 names.", call. = FALSE)
  }
  if (anyNA(x) || any(!nzchar(x))) {
    stop(what, " must not contain empty names.", call. = FALSE)
  }
  if (anyDuplicated(x)) stop(what, " must be unique.", call. = FALSE)
  x
}

#' Validate a length-2 finite increasing range
#' @noRd
check_range <- function(r, what) {
  if (!is.numeric(r) || length(r) != 2L || !all(is.finite(r)) || !(r[1] < r[2])) {
    stop(what, " must be two finite numbers with the first less than the second.",
         call. = FALSE)
  }
  r
}
