#' Sample a data frame from a DataCraftR spec
#'
#' Turns a spec (what was drawn) into a data frame. Population tools draw `n`
#' rows using `seed`; literal tools return exactly what was drawn and ignore
#' `n` and `seed`. The session's random number state (`.Random.seed`) is
#' left as it was.
#'
#' @param spec A `dcr_spec` object, e.g. from [dcr_spec()].
#' @param n Number of rows for population tools; defaults to `spec$n`.
#' @param seed Optional integer seed; defaults to `spec$seed`.
#' @return A data frame with attribute `"dcr_spec"` holding the spec used (with
#'   `n` and `seed` set to the values used).
#' @examples
#' if (FALSE) {
#'   df <- dcr_sample(dcr_spec(my_df), n = 200, seed = 1)
#' }
#' @export
dcr_sample <- function(spec, n = NULL, seed = NULL) {
  if (!inherits(spec, "dcr_spec")) {
    stop("spec must be a dcr_spec object.", call. = FALSE)
  }
  if (identical(spec_kind(spec), "population")) {
    n <- n %||% spec$n
    if (!is.numeric(n) || length(n) != 1L || is.na(n) || !is.finite(n) ||
        n < 1 || n != round(n)) {
      stop("n must be a single whole number >= 1.", call. = FALSE)
    }
    n <- as.integer(n)
    # Leave the caller's random number stream untouched (like
    # withr::with_seed()): restore .Random.seed, or remove it if it did not
    # exist, also when no seed is given and one is drawn here.
    old_seed <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit({
      if (is.null(old_seed)) {
        if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
          rm(".Random.seed", envir = globalenv())
        }
      } else {
        assign(".Random.seed", old_seed, envir = globalenv())
      }
    }, add = TRUE)
    seed <- seed %||% spec$seed
    if (is.null(seed)) seed <- sample.int(1e6, 1L)
    set.seed(seed)
    spec$n <- n
    spec$seed <- seed
    res <- sample_spec(spec, n)
  } else {
    res <- sample_spec(spec, NULL)
  }
  attr(res, "dcr_spec") <- spec
  res
}
