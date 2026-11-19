#' HTML dependencies of the gadget (D3 + the DataCraftR engine)
#'
#' Served from the installed package (`inst/www`), never from a CDN. For each
#' name in `tools`, `dcr/tools/<name>.js` is included when it exists. Load
#' order: D3, `core.js`, tool scripts, then `shiny-binding.js` (which
#' instantiates the registered tools).
#'
#' @param tools Character vector of tool names.
#' @return A list of two `htmlDependency` objects.
#' @noRd
dcr_dependencies <- function(tools = character()) {
  www <- system.file("www", package = "DataCraftR")
  dcr_dir <- file.path(www, "dcr")
  tool_js <- file.path("tools", paste0(tools, ".js"))
  tool_js <- tool_js[file.exists(file.path(dcr_dir, tool_js))]
  list(
    htmltools::htmlDependency(
      name = "d3", version = "7.9.0",
      src = c(file = file.path(www, "lib", "d3")),
      script = "d3.min.js"
    ),
    htmltools::htmlDependency(
      name = "dcr", version = "0.4.0",
      src = c(file = dcr_dir),
      script = c("core.js", tool_js, "shiny-binding.js"),
      stylesheet = "dcr.css"
    )
  )
}

#' Bootstrap 5 theme of the gadget
#' @noRd
dcr_theme <- function() {
  bslib::bs_theme(
    version = 5,
    primary = "#447099",
    "body-bg" = "#ffffff",
    "body-color" = "#1f2933",
    "border-color" = "#dfe3e8",
    base_font = paste("system-ui, -apple-system, 'Segoe UI', Roboto,",
                      "'Helvetica Neue', Arial, sans-serif"),
    "font-size-base" = "0.8125rem"
  )
}
