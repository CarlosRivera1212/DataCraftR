dcr_store_dir <- function() {
  dir <- tools::R_user_dir("DataCraftR", "data")
  if (!dir.exists(dir)) suppressWarnings(dir.create(dir, recursive = TRUE))
  dir
}

dcr_save <- function(spec, time = Sys.time()) {
  dir <- dcr_store_dir()
  tryCatch({
    if (!dir.exists(dir)) stop("directory does not exist", call. = FALSE)
    base <- paste0(spec$tool, "_", format(time, "%Y%m%d_%H%M%S"))
    id <- base
    k <- 1L
    while (file.exists(file.path(dir, paste0(id, ".rds")))) {
      k <- k + 1L
      id <- paste0(base, "_", k)
    }
    saveRDS(spec, file.path(dir, paste0(id, ".rds")))
    id
  }, error = function(e) {
    stop("Could not save to ", dir, ": ", conditionMessage(e), call. = FALSE)
  })
}

dcr_id_path <- function(id) {
  ok <- is.character(id) && length(id) == 1L && !is.na(id) &&
    grepl("^[a-z]+_[0-9]{8}_[0-9]{6}(_[0-9]+)?$", id)
  if (!ok) {
    stop("Invalid id. Use dcr_list() to see saved ids.", call. = FALSE)
  }
  path <- file.path(dcr_store_dir(), paste0(id, ".rds"))
  if (!file.exists(path)) {
    stop("No saved spec with id '", id, "'. Use dcr_list() to see saved ids.",
         call. = FALSE)
  }
  path
}

#' Load a saved DataCraftR dataset
#'
#' Tools used from the RStudio Addins menu save their spec in the user data
#' directory (`tools::R_user_dir("DataCraftR", "data")`) and insert
#' `df <- dcr_load("<id>")` into your script. Literal tools (scatter, count,
#' mosaic) return exactly what was drawn. Population tools (boxplot, histogram,
#' density, bivariate, regression, radar) re-sample using the stored seed, so
#' the same data comes back, unless you give a different `seed`.
#'
#' @param id Id of a saved spec, as shown by [dcr_list()].
#' @param n Number of rows for population tools (per group for bivariate,
#'   regression and radar); defaults to the stored `n`. The cap of 1e6 rows in
#'   total is checked when the drawing is made, not when `n` is overridden here.
#' @param seed Integer seed for population tools; defaults to the stored seed.
#' @return A data frame (see [dcr_sample()]).
#' @examples
#' if (FALSE) {
#'   dcr_list()
#'   df <- dcr_load("boxplot_20261117_153012")
#' }
#' @export
dcr_load <- function(id, n = NULL, seed = NULL) {
  spec <- readRDS(dcr_id_path(id))
  dcr_sample(spec, n, seed %||% spec$seed)
}

#' List saved DataCraftR datasets
#'
#' @return A data frame with columns `id`, `tool`, `created` and `n` (the total
#'   number of rows), newest first. Files in the store that are not readable specs are ignored.
#' @examples
#' if (FALSE) {
#'   dcr_list()
#' }
#' @export
dcr_list <- function() {
  files <- list.files(dcr_store_dir(), pattern = "[.]rds$", full.names = TRUE)
  rows <- lapply(files, function(f) {
    spec <- tryCatch(readRDS(f), error = function(e) NULL)
    if (!inherits(spec, "dcr_spec")) return(NULL)
    n <- tryCatch(spec_n(spec), error = function(e) NA_integer_)
    data.frame(id = tools::file_path_sans_ext(basename(f)),
               tool = as.character(spec$tool),
               created = as.character(spec$created %||% NA_character_),
               n = as.numeric(n %||% NA_real_),
               stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0L) {
    return(data.frame(id = character(0), tool = character(0),
                      created = character(0), n = numeric(0),
                      stringsAsFactors = FALSE))
  }
  res <- do.call(rbind, rows)
  res <- res[order(res$created, res$id, decreasing = TRUE), , drop = FALSE]
  rownames(res) <- NULL
  res
}

#' Delete a saved DataCraftR dataset
#'
#' @param id Id of a saved spec, as shown by [dcr_list()].
#' @return `invisible(TRUE)`.
#' @examples
#' if (FALSE) {
#'   dcr_delete("boxplot_20261117_153012")
#' }
#' @export
dcr_delete <- function(id) {
  path <- dcr_id_path(id)
  if (!isTRUE(file.remove(path))) {
    stop("Could not delete '", id, "'.", call. = FALSE)
  }
  invisible(TRUE)
}
