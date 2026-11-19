# Internal S3 generics; tool tasks add methods in this namespace.
spec_from_json <- function(x) UseMethod("spec_from_json")
sample_spec <- function(spec, n) UseMethod("sample_spec")
spec_stats <- function(spec) UseMethod("spec_stats")
spec_n <- function(spec) UseMethod("spec_n")
spec_is_empty <- function(spec) UseMethod("spec_is_empty")
spec_kind <- function(spec) UseMethod("spec_kind")

new_dcr_spec <- function(tool, ..., n = NULL, seed = NULL, created = Sys.time()) {
  structure(
    c(list(tool = tool, version = 1L,
           created = format(created, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           n = n, seed = seed),
      list(...)),
    class = c(paste0("dcr_spec_", tool), "dcr_spec")
  )
}

as_dcr_spec <- function(x) {
  tool <- x[["tool"]]
  if (!is.character(tool) || length(tool) != 1L) {
    stop("Unknown DataCraftR tool: ", paste(format(tool), collapse = ""), call. = FALSE)
  }
  cls <- paste0("dcr_json_", tool)
  if (is.null(utils::getS3method("spec_from_json", cls, optional = TRUE,
                                 envir = environment(spec_from_json)))) {
    stop("Unknown DataCraftR tool: ", tool, call. = FALSE)
  }
  spec_from_json(structure(x, class = cls))
}

#' Recover the spec behind a DataCraftR data frame
#'
#' @param df A data frame returned by a DataCraftR tool.
#' @return A `dcr_spec` object.
#' @export
dcr_spec <- function(df) {
  s <- attr(df, "dcr_spec", exact = TRUE)
  if (is.null(s)) stop("df was not created by DataCraftR", call. = FALSE)
  s
}

#' @export
print.dcr_spec <- function(x, ...) {
  cat(sprintf("<dcr_spec: %s, n = %s, seed = %s, created %s>\n",
              x$tool, format(x$n %||% NA), format(x$seed %||% NA), x$created))
  invisible(x)
}

# Shiny input handler for the JS spec (a JSON string). Never throws: an
# invalid spec becomes a `dcr_spec_error` so the session survives and the
# gadget can show the message.
dcr_spec_input_handler <- function(x, session, name) {
  if (is.null(x)) return(NULL)
  tryCatch(
    as_dcr_spec(jsonlite::fromJSON(x, simplifyVector = TRUE)),
    error = function(e) {
      structure(list(message = conditionMessage(e)), class = "dcr_spec_error")
    }
  )
}

.onLoad <- function(libname, pkgname) {
  shiny::registerInputHandler("dcr.spec", dcr_spec_input_handler, force = TRUE)
}
