#' Reproducible code for a saved drawing
#'
#' @param id Store id returned by `dcr_save()`.
#' @param spec A `dcr_spec`.
#' @return Character vector of three lines.
#' @noRd
dcr_code <- function(id, spec) {
  created <- as.POSIXct(spec$created, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  header <- paste0("# DataCraftR \u00b7 ", spec$tool, " \u00b7 ",
                   format(created, "%Y-%m-%d %H:%M", tz = ""),
                   " \u00b7 n = ", spec_n(spec))
  load_line <- if (identical(spec_kind(spec), "population")) {
    paste0("df <- dcr_load(\"", id, "\", seed = ",
           format(spec$seed, scientific = FALSE, trim = TRUE), ")")
  } else {
    paste0("df <- dcr_load(\"", id, "\")")
  }
  c(header, load_line,
    paste0("# write.csv(df, \"", spec$tool,
           ".csv\", row.names = FALSE)   # save into your project"))
}
