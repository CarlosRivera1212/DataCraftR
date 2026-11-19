# DataCraftR 0.5.1

* New tool `dcr_density()`: sculpt smooth density curves (Pull / Paint brush
  modes), multiple variables, exact sampling from the drawn curve.
* Drawing tools recover from a stroke left open by a missed pointer event (no
  more stuck canvas).

# DataCraftR 0.4.0

The four tools were rebuilt on one shared engine.

## Breaking changes

* The tools now return the data frame (`df <- dcr_scatter()`) instead of
  writing a temporary `.rds` file. The result carries its spec, available with
  `dcr_spec(df)`; `dcr_sample(dcr_spec(df))` reproduces it.
* New names: `dcr_scatter()`, `dcr_boxplot()`, `dcr_histogram()` and
  `dcr_count()`.
* `scatter_dcr()`, `boxplot_dcr()`, `histogram_dcr()` and `count_dcr()` are
  deprecated and will be removed in a later release. They now also return
  the data frame (invisibly) instead of writing a temporary `.rds` file,
  while keeping the Addins behaviour (Done saves the drawing and inserts code
  into the active document).
* The Addins are now named *Scatter*, *Boxplot*, *Histogram* and *Count*. The
  old addin entries are no longer registered, so RStudio keyboard shortcuts
  bound to them must be re-bound to the new addins (*Tools > Modify Keyboard
  Shortcuts*).
* From the Addins menu, drawings are saved to
  `tools::R_user_dir("DataCraftR", "data")` instead of `tempdir()`.

## New features

* `dcr_load()`, `dcr_list()` and `dcr_delete()` manage saved drawings, and
  `dcr_sample()` / `dcr_spec()` regenerate data from a spec.
* New Count tool, and a shared interface with undo/redo, stats and a seed.
* Inserted code is three lines that load the saved drawing, always placed on
  a new line after the cursor (never mid-line) and without needing ggplot2.
* Pointer events: touch and pen now work, not only the mouse.

## Bug fixes

* Pressing Save more than once no longer saves or inserts code several times,
  and unchanged data is saved too.
* The scatter tool no longer sends each click twice.
* The histogram respects the minimum of the X range, and recomputes its bins
  when the X range changes.
* The inserted code reproduces the drawn histogram bins.
* The boxplot median is no longer forced to the midpoint of Q1 and Q3, so
  asymmetric boxes are possible.
* The scatter drawing is kept when the number of groups changes.
* DataCraftR no longer masks `grDevices::palette()`.
* No code snippet depends on a package that is not installed.
* D3 is bundled instead of loaded from two unpinned CDNs, so the tools work
  offline.

## Dependencies

* Dropped RcppColors, shinyWidgets and bsicons.
* Imports are now bslib, htmltools, jsonlite, rstudioapi, shiny, stats, tools
  and utils.
