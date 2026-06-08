.onLoad <- function(libname, pkgname) {
  shiny::addResourcePath("assets", system.file("assets", package = pkgname))
}

.onUnload <- function(libpath) {
  shiny::removeResourcePath("assets")
}
