# Old v0.3 names, kept for existing shortcuts and scripts.

#' Deprecated functions
#'
#' These v0.3 names still open the matching gadget but now behave like the
#' Addins menu: **Done** saves the drawing and inserts code into the active
#' document. Use `dcr_scatter()`, `dcr_boxplot()`, `dcr_histogram()` and
#' `dcr_count()` instead, which return the data frame.
#'
#' @return The value of the gadget, invisibly.
#' @name DataCraftR-deprecated
#' @keywords internal
NULL

#' @rdname DataCraftR-deprecated
#' @export
scatter_dcr <- function() {
  .Deprecated("dcr_scatter", package = "DataCraftR")
  invisible(run_dcr_gadget(scatter_tool(), "addin"))
}

#' @rdname DataCraftR-deprecated
#' @export
boxplot_dcr <- function() {
  .Deprecated("dcr_boxplot", package = "DataCraftR")
  invisible(run_dcr_gadget(boxplot_tool(), "addin"))
}

#' @rdname DataCraftR-deprecated
#' @export
histogram_dcr <- function() {
  .Deprecated("dcr_histogram", package = "DataCraftR")
  invisible(run_dcr_gadget(histogram_tool(), "addin"))
}

#' @rdname DataCraftR-deprecated
#' @export
count_dcr <- function() {
  .Deprecated("dcr_count", package = "DataCraftR")
  invisible(run_dcr_gadget(count_tool(), "addin"))
}
