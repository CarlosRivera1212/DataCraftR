test_that("dcr_icon builds the shared 20 px decorative glyph", {
  svg <- dcr_icon("pull")
  html <- as.character(svg)
  expect_match(html, 'viewBox="0 0 20 20"', fixed = TRUE)
  expect_match(html, 'aria-hidden="true"', fixed = TRUE)
  expect_match(html, 'stroke="currentColor"', fixed = TRUE)
  expect_match(html, 'stroke-width="1.5"', fixed = TRUE)
  expect_match(html, 'stroke-linecap="round"', fixed = TRUE)
  expect_match(as.character(dcr_icon("flat")), 'fill-opacity="0.15"', fixed = TRUE)
  expect_error(dcr_icon("nope"), "Unknown icon")
  expect_false(grepl("[^\x01-\x7f]", html))
})

test_that("every defined icon renders", {
  for (nm in names(dcr_icon_defs)) {
    expect_match(as.character(dcr_icon(nm)), paste0('data-icon="', nm, '"'),
                 fixed = TRUE)
  }
})

# tool, kind (value = seg option, action = data-dcr-action), key, icon, label
icon_table <- function() {
  rows <- list(
    c("scatter", "value", "spray", "spray", "Spray"),
    c("scatter", "value", "point", "point", "Point"),
    c("scatter", "value", "erase", "erase", "Erase"),
    c("boxplot", "value", "normal", "normal", "Normal"),
    c("boxplot", "value", "uniform", "flat", "Uniform"),
    c("boxplot", "action", "align", "medians", "Align medians"),
    c("boxplot", "action", "reset", "reset", "Reset boxes"),
    c("histogram", "action", "flat", "bars", "Flat"),
    c("histogram", "action", "reset", "reset", "Reset"),
    c("density", "value", "pull", "pull", "Pull"),
    c("density", "value", "paint", "paint", "Paint"),
    c("density", "action", "bell", "normal", "Bell"),
    c("density", "action", "flat", "flat", "Flat"),
    c("density", "action", "skew", "skew", "Skewed"),
    c("bivariate", "value", "handles", "handles", "Handles"),
    c("bivariate", "value", "gestures", "gesture", "Gestures"),
    c("bivariate", "action", "reset-axes", "axes", "Reset axes"),
    c("count", "action", "align-top", "align_top", "Align top"),
    c("count", "action", "align-middle", "align_middle", "Align middle"),
    c("count", "action", "align-bottom", "align_bottom", "Align bottom"),
    c("mosaic", "action", "independent", "independent", "Independent"),
    c("mosaic", "action", "uniform", "uniform", "Uniform"),
    c("regression", "value", "curve", "curve", "Curve"),
    c("regression", "value", "error", "error", "Error"),
    c("regression", "value", "pull", "pull", "Pull"),
    c("regression", "value", "paint", "paint", "Paint"),
    c("regression", "action", "apply-equation", "check", "Apply"),
    c("regression", "action", "fit-y", "fit", "Fit to y"),
    c("regression", "action", "resample", "dice", "Resample"),
    c("radar", "value", "mean", "mean", "Mean"),
    c("radar", "value", "spread", "spread", "Spread"),
    c("radar", "action", "preset-tight", "tight", "Tight (5 %)"),
    c("radar", "action", "preset-medium", "medium", "Medium (10 %)"),
    c("radar", "action", "preset-wide", "wide", "Wide (20 %)"),
    c("radar", "action", "same-all", "copy", "Same for all groups"),
    c("radar", "action", "resample", "dice", "Resample")
  )
  as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE) |>
    stats::setNames(c("tool", "kind", "key", "icon", "label"))
}

test_that("every tool's sidebar draws the approved icon on each control", {
  tab <- icon_table()
  for (i in seq_len(nrow(tab))) {
    r <- tab[i, ]
    tool <- get(paste0(r$tool, "_tool"))()
    html <- as.character(tool$sidebar(tool$options))
    attr <- if (r$kind == "value") "data-value" else "data-dcr-action"
    pattern <- sprintf('%s="%s"[^>]*>[[:space:]]*<svg[^>]*data-icon="%s"',
                       attr, r$key, r$icon)
    expect_match(html, pattern, perl = TRUE,
                 label = paste(r$tool, r$key))
    # the visible label stays next to the icon (or in title/aria-label)
    expect_true(grepl(r$label, html, fixed = TRUE), label = paste(r$tool, "label", r$label))
  }
})

test_that("icons are decorative and seg/action buttons keep their label", {
  tool <- radar_tool()
  html <- as.character(tool$sidebar(tool$options))
  svgs <- regmatches(html, gregexpr("<svg[^>]*>", html))[[1]]
  expect_true(length(svgs) > 0)
  expect_true(all(grepl('aria-hidden="true"', svgs, fixed = TRUE)))
  expect_match(html, 'aria-label="Mean"', fixed = TRUE)
  # labelled action buttons show their text
  tool <- count_tool()
  html <- as.character(tool$sidebar(tool$options))
  expect_match(html, "</svg>[[:space:]]*Align top[[:space:]]*</button>")
})

test_that("the toolbar uses icons with accessible names", {
  html <- as.character(dcr_gadget_ui(helper_tool()))
  for (a in c("undo", "redo", "clear")) {
    pattern <- sprintf('data-dcr-action="%s"[^>]*>[[:space:]]*<svg[^>]*data-icon="%s"', a, a)
    expect_match(html, pattern, perl = TRUE)
  }
  expect_match(html, 'aria-label="Undo (Ctrl+Z)"', fixed = TRUE)
  expect_match(html, 'aria-label="Redo (Ctrl+Shift+Z)"', fixed = TRUE)
  expect_match(html, 'aria-label="Clear"', fixed = TRUE)
  expect_false(grepl("\u21b6|\u232b", html))
  expect_match(html, 'data-icon="chevron"', fixed = TRUE)
})
