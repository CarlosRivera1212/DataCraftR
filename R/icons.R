# One shared icon set (20 x 20 viewBox, stroke currentColor 1.5, round caps and
# joins, filled areas at fill-opacity .15). Each glyph is a list of SVG
# elements; helpers below build them with htmltools.

icon_path <- function(d, fill = FALSE) {
  list(tag = "path", d = d,
       fill = if (fill) "currentColor", `fill-opacity` = if (fill) "0.15")
}

# Solid dots (the only fully filled shapes), drawn without a stroke.
icon_dots <- function(xy, r = 1.2) {
  list(tag = "g", fill = "currentColor", stroke = "none",
       kids = lapply(seq_len(nrow(xy)), function(i) {
         list(tag = "circle", cx = xy[i, 1], cy = xy[i, 2], r = r)
       }))
}

dcr_icon_defs <- list(
  curve = list(icon_path("M2 16 C8 16 9 5 18 4")),
  error = list(icon_path("M2 12 C8 12 9 4 18 3 L18 10 C9 11 8 19 2 19 Z", TRUE)),
  pull = list(icon_path("M10 3 V17 M6.5 6.5 L10 3 L13.5 6.5 M6.5 13.5 L10 17 L13.5 13.5")),
  paint = list(icon_path("M17 3 L10 10 M10 10 C6.5 9.5 5 12.5 3.5 17 C8 16.5 11 15 10.5 11.5")),
  mean = list(icon_path("M10 2 L17 7 L14.5 16 L5.5 16 L3 7 Z", TRUE)),
  spread = list(icon_path("M10 1.5 L18 7 L15 17 L5 17 L2 7 Z M10 6 L13.5 8.5 L12.2 13 L7.8 13 L6.5 8.5 Z")),
  tight = list(icon_path("M10 3 V17 M7 6 L10 3 L13 6 M7 14 L10 17 L13 14")),
  medium = list(icon_path("M10 2 V18 M6 6 L10 2 L14 6 M6 14 L10 18 L14 14")),
  wide = list(icon_path("M10 1 V19 M5 6 L10 1 L15 6 M5 14 L10 19 L15 14 M4 10 H16")),
  spray = list(icon_dots(rbind(c(5, 6), c(9, 4), c(13, 7), c(16, 4.5), c(7, 10.5),
                               c(12, 11.5), c(16, 12), c(9.5, 15.5), c(14, 16)))),
  point = list(
    list(tag = "circle", cx = 10, cy = 10, r = 3.5, fill = "currentColor",
         `fill-opacity` = "0.15"),
    icon_path("M10 2.5 V5 M10 15 V17.5 M2.5 10 H5 M15 10 H17.5")),
  erase = list(icon_path("M3.5 12.5 L11 5 L16 10 L9.5 16.5 H6.5 Z M7.5 8.5 L13 14 M10 16.5 H17")),
  normal = list(icon_path("M2 16 C6 16 7 4 10 4 C13 4 14 16 18 16")),
  flat = list(icon_path("M3 6 H17 V16 H3 Z", TRUE)),
  skew = list(icon_path("M2 16 C4 16 5 4 7 4 C10 4 11 15 18 16")),
  medians = list(icon_path("M3.5 6 H8.5 V14 H3.5 Z M11.5 4 H16.5 V16 H11.5 Z", TRUE),
                 icon_path("M1.5 10 H18.5")),
  reset = list(icon_path("M16 10 A6 6 0 1 1 13.5 5 M16.5 3 V6.5 H13")),
  bars = list(icon_path("M3 7 H17 V16 H3 Z M7.5 7 V16 M12.5 7 V16")),
  handles = list(
    list(tag = "ellipse", cx = 10, cy = 10, rx = 7, ry = 3.8,
         transform = "rotate(-30 10 10)", fill = "currentColor",
         `fill-opacity` = "0.15"),
    list(tag = "circle", cx = 4.3, cy = 13.3, r = 1.6, fill = "#fff"),
    list(tag = "circle", cx = 15.7, cy = 6.7, r = 1.6, fill = "#fff")),
  gesture = list(icon_path("M4 15 C6 8 10 6 16 6 M13 3 L16 6 L13 9"),
                 list(tag = "circle", cx = 4, cy = 15, r = 1.5,
                      fill = "currentColor")),
  axes = list(icon_path("M3 3 V17 H17 M14.5 12 A3.5 3.5 0 1 1 13 8 M14.8 6 V8.8 H12")),
  align_top = list(icon_path("M2.5 3.5 H17.5 M5 3.5 H8 V15 H5 Z M12 3.5 H15 V10 H12 Z")),
  align_middle = list(icon_path("M2.5 10 H17.5 M5 4 H8 V16 H5 Z M12 6.5 H15 V13.5 H12 Z")),
  align_bottom = list(icon_path("M2.5 16.5 H17.5 M5 5 H8 V16.5 H5 Z M12 10 H15 V16.5 H12 Z")),
  independent = list(icon_path("M3 3 H17 V17 H3 Z M8 3 V17 M3 12 H17")),
  uniform = list(icon_path("M3 3 H17 V17 H3 Z M7.7 3 V17 M12.3 3 V17 M3 7.7 H17 M3 12.3 H17")),
  check = list(icon_path("M4 10.5 L8.5 15 L16 5.5")),
  fit = list(icon_path("M16 3 V17 M14 5 L16 3 L18 5 M14 15 L16 17 L18 15 M2 14 C6 14 8 7 13 6")),
  dice = list(
    list(tag = "rect", x = 3, y = 3, width = 14, height = 14, rx = 3),
    icon_dots(rbind(c(7.3, 7.3), c(12.7, 12.7), c(10, 10)))),
  copy = list(icon_path("M7 7 H16 V16 H7 Z M4 13 V4 H13")),
  undo = list(icon_path("M6 8 H12 A4 4 0 0 1 12 16 H8 M9 4.5 L5.5 8 L9 11.5")),
  redo = list(icon_path("M14 8 H8 A4 4 0 0 0 8 16 H12 M11 4.5 L14.5 8 L11 11.5")),
  clear = list(icon_path("M3.5 5.5 H16.5 M8 5.5 V3.5 H12 V5.5 M5 5.5 L6 17 H14 L15 5.5 M8.5 8.5 V14 M11.5 8.5 V14")),
  chevron = list(icon_path("M5 8 L10 13 L15 8"))
)

icon_element <- function(el) {
  kids <- el$kids
  el$kids <- NULL
  tag <- el$tag
  el$tag <- NULL
  el <- Filter(Negate(is.null), el)
  htmltools::tag(tag, c(el, lapply(kids, icon_element)))
}

#' Inline SVG icon of the shared set
#'
#' Decorative (`aria-hidden`): the visible label next to it is the accessible
#' name.
#' @param name A key of `dcr_icon_defs`.
#' @noRd
dcr_icon <- function(name) {
  def <- dcr_icon_defs[[name]]
  if (is.null(def)) stop("Unknown icon: ", name, call. = FALSE)
  htmltools::tag(
    "svg",
    c(list(xmlns = "http://www.w3.org/2000/svg", viewBox = "0 0 20 20",
           width = "20", height = "20", class = "dcr-i", `aria-hidden` = "true",
           focusable = "false", `data-icon` = name, fill = "none",
           stroke = "currentColor", `stroke-width` = "1.5",
           `stroke-linecap` = "round", `stroke-linejoin` = "round"),
      lapply(def, icon_element))
  )
}

#' Sidebar action button: optional icon before the visible label
#'
#' @param action The `data-dcr-action` the tool handles.
#' @param primary Draw it as the confirming (primary blue) action.
#' @noRd
dcr_action_button <- function(action, label, icon = NULL, primary = FALSE) {
  htmltools::tags$button(
    type = "button",
    class = paste("btn btn-sm dcr-act",
                  if (primary) "btn-primary" else "btn-light"),
    `data-dcr-action` = action,
    if (!is.null(icon)) dcr_icon(icon),
    label
  )
}

#' Named list of icons (for `dcr_seg_input(icons = )`)
#' @noRd
dcr_icons <- function(...) {
  keys <- c(...)
  stats::setNames(lapply(keys, dcr_icon), names(keys) %||% keys)
}
