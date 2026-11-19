# DataCraftR manual smoke checklist

JS has no automated tests in v0.4 (`RS tools/check-js.R` covers syntax and the
DOM-free state logic only). Run this list in RStudio before a release, after
`devtools::install()` (or `devtools::load_all()` for the console items).

How to run each tool:

- **Console mode**: `df <- dcr_<tool>()` in the console (e.g. `dcr_scatter()`).
  Done returns the data frame; Cancel returns `NULL` invisibly.
- **Addin mode**: open an R script, put the cursor on an empty line, then
  *Addins > DataCraftR > <Tool>*. Done saves the spec under
  `tools::R_user_dir("DataCraftR", "data")` and inserts 3 lines (comment,
  `df <- dcr_load("<id>")`, commented `write.csv`) below the cursor line.
- Outside RStudio the gadget opens in the browser.
- Use the pointer you have: mouse, and touch or pen if available.

Tick each item; note failures with the tool, step and what happened.

## Scatter

Start: `df <- dcr_scatter()` (groups A, B, C; x and y ranges 0 to 10).

- [ ] Layout: sidebar with Active group, Groups, Brush (Spray/Point/Erase,
      Size `[ ]`, Density), Axes (x range, y range), Names (x, y, group);
      plot area is square in data units (resize the window: it stays square,
      centred, axes redraw).
- [ ] Draw 3 groups: spray with A, then press `2` and spray B, click C in the
      Active group selector and spray C. Points take the group colour; holding
      still keeps adding points (time-based), moving the pointer slowly does
      not add more than holding still. `n` and the stats table update after
      each stroke (per group n, means, sds, r).
- [ ] Point mode: each click adds exactly one point of the active group.
- [ ] Spraying near an edge never puts points outside the axes ranges.
- [ ] Undo/redo/clear via the toolbar buttons: one stroke is undone as a whole;
      Clear removes all points but keeps groups, ranges and names; Clear is
      undoable.
- [ ] Undo/redo via `Ctrl+Z` / `Ctrl+Shift+Z` (Cmd on macOS); while typing in a
      sidebar text field, `Ctrl+Z` undoes the text, not the drawing.
- [ ] Brush keys: `]` grows and `[` shrinks the brush circle; the Size slider
      follows (0.01 to 0.5). Moving the slider changes the circle. Pressing
      `1`-`3` moves the Active group selector.
- [ ] Erase mode: dragging removes points of every group under the (dashed)
      circle; one erase stroke = one undo step.
- [ ] Ranges: after drawing, set x range to `-5` and `5`: the points keep their
      x values (the drawn cloud moves right / partly out of view), nothing is
      reinterpreted; `df` later shows the original values. Undo restores the
      range and the sidebar fields show it again.
- [ ] Invalid range (x min `5`, max `5`, or min > max): a notification
      appears and the plot keeps the old range.
- [ ] Rename a group: change Groups to `A, X, C` and press Enter: B's points
      become X (same colour), the selector shows X.
- [ ] Remove a group: change Groups to `A, C`: only X's points disappear, a
      message "N points of X removed - Ctrl+Z to undo" shows in the canvas;
      `Ctrl+Z` (outside the field) brings group and points back and the Groups
      field shows `A, X, C` again. Adding `D` keeps all points.
- [ ] Invalid groups (`A, A`, `A, , B`, empty, 11 names): notification, no change.
- [ ] Edit then draw: type a new x range (or Groups) and, without pressing
      Enter, immediately spray on the canvas. The stroke and the field change
      are two separate undo steps (`Ctrl+Z` once undoes the field change, a
      second time the whole stroke); the stroke's points are not mixed into
      the field's step.
- [ ] Rapid undo: after several group/range edits and a big drawing (~20 000
      points), press `Ctrl+Z` three times quickly, then `Ctrl+Shift+Z`: redo
      still works (no extra history entries appear), and the sidebar fields
      end showing the current state.
- [ ] Spray, then drag the pointer outside the window and release there (or
      switch window with Alt+Tab while pressing): spraying stops; the next
      press starts a new stroke.
- [ ] Names: set x, y, group to `height`, `weight`, `species`; axis titles
      update; duplicates give a notification.
- [ ] Done with nothing drawn: "Nothing to return yet", gadget stays open.
- [ ] Done from the console returns `df` with columns `height`, `weight`,
      `species` (or the names you set), `species` a factor whose levels are the
      groups in order (including groups with no points); `nrow(df)` equals `n`.
- [ ] Edit then Done: draw some points, then type in a field and, without
      pressing Enter or clicking elsewhere, click Done directly. Try Groups
      (`A, X, C`: `df$group` has X instead of B), x range (`-5`, `20`: the
      spec's `xlim`) and Names (`h` for x: the first column is `h`). An
      invalid edit (`A, A`) still returns the data with the old groups.
- [ ] Big drawing: hold spray at Density 200 with a large brush for ~30 s;
      drawing stays smooth, Done is quick.
- [ ] Done via *Addins > DataCraftR > Scatter* inserts 3 lines; running the
      `dcr_load()` line reproduces exactly the drawn points
      (`identical(df, dcr_load(id))` after a second load).
- [ ] Touch / pen (if available): spray, point and erase work; the page does
      not scroll while drawing.
- [ ] Cancel (button and `Esc` outside a field) returns `NULL`; closing the
      window also returns `NULL`.

## Boxplot

- [ ] Open `dcr_boxplot(ylim = c(0, 100))`: three boxes (V1-V3) at 25/50/75 of
      the range, colours from the palette, whiskers at the 1st/99th
      percentiles of the drawn distribution; stats table lists q1, median, q3.
- [ ] Drag the Q1, median and Q3 handles (edge lines / circles) independently:
      they never cross (minimum gap 1 % of the range) and stay inside the
      y range. Dragging the box body moves all three together.
- [ ] One drag = one undo step (`Ctrl+Z` undoes the whole drag, `Ctrl+Shift+Z`
      redoes it).
- [ ] Drag a box so a whisker leaves the visible range: the range does not
      change during the drag; on release the y range expands (sidebar fields
      update) and a single `Ctrl+Z` undoes both the drag and the expansion.
- [ ] Asymmetric box (e.g. Q1 close to the median, Q3 far): Done returns `df`
      whose `boxplot(df)` is visibly skewed in the same way.
- [ ] Distribution Uniform vs Normal: whiskers move (uniform is wider);
      `df` columns look uniform / bell-shaped on each side of the median.
- [ ] Align medians: all medians go to the middle of the y range, each box
      keeps its shape. Reset boxes: all back to 25/50/75 %. Both undoable.
- [ ] Variables: add `D` (new box at the reset position, others untouched);
      rename `V2` to `X` (box keeps its values); remove one (others keep
      values). Invalid (`A, A`, empty, 11 names): notification, no change.
- [ ] Keys `1`-`3` select a variable (outside fields); clicking a box also
      selects it (bold outline).
- [ ] Sample size: `n` = 0, 1.5 or 2e6 gives a notification and no change;
      `n = 1e5` then Done is fast and `nrow(df) == 1e5`.
- [ ] Invalid y range (`5`, `5` or reversed): notification, plot unchanged.
- [ ] Edit then Done: type in a field and click Done directly, without
      Enter or a click elsewhere. Sample size `37`: `nrow(df) == 37`.
      Variables `V1, V2`: two columns. y range `0`, `50`:
      `dcr_spec(df)$ylim` is 0, 50. Seed `123`: `dcr_spec(df)$seed == 123`.
- [ ] Release the pointer outside the window mid-drag: the drag ends and the
      next press starts a new one.
- [ ] Done via *Addins > DataCraftR > Boxplot* inserts the code; running it
      reproduces the same data.
- [ ] Cancel (button and `Esc` outside a field) returns `NULL`.

## Histogram

- [ ] Open `dcr_histogram(xlim = c(10, 20), nbins = 10)`: ten empty bars span
      exactly 10 to 20 (first and last bar touch the frame edges); the Y axis
      is titled "relative weight" (0 to 1).
- [ ] Press and drag across the bars: each bar under the pointer jumps to the
      pointer's height. A very fast sweep leaves no gaps (skipped bars are
      interpolated). Dragging outside the frame clamps to the first/last bar
      and to heights 0 and 1.
- [ ] One drag = one undo step (`Ctrl+Z` undoes the whole drag, `Ctrl+Shift+Z`
      redoes it). Only the active variable changes.
- [ ] Each filled bar shows its expected count `round(w / sum(w) * n)` for the
      active variable; labels update while painting and change with `n`; no
      labels while all bars are zero.
- [ ] Add variables (`dcr_histogram(c("A", "B"))`): inactive variables show as
      faint outlines, the active one is filled; keys `1`-`2` or the buttons
      switch the active variable.
- [ ] Flat sets the active variable's bars to half height; Reset zeroes them.
      Both undoable; pressing Flat twice adds one undo step only.
- [ ] Draw a bump, then change the number of bins (e.g. 10 to 20 to 5): the
      shape and the tallest bar height are kept; one `Ctrl+Z` undoes the
      change. Invalid bins (0, 101, 2.5): notification, no change.
- [ ] Change the x range after drawing (e.g. 10-20 to 0-20): the drawing keeps
      its place on the axis and the new bars outside the old range are empty;
      undo restores it.
- [ ] Variables: add `D` (new empty histogram, others untouched); rename `V2`
      to `X` (bars kept); remove one (others keep their bars). Invalid
      (`A, A`, empty, 11 names): notification, no change.
- [ ] Data in the bin edges: with `xlim = c(10, 20)` Done returns values with
      `min(df$V1) >= 10` and `max(df$V1) <= 20` that fall only in drawn
      (non-zero) bars; `hist(df$V1, breaks = seq(10, 20, 1))` matches the
      painted shape.
- [ ] `n` = 0, 1.5 or 2e6 gives a notification and no change; `n = 1e5` then
      Done is fast and `nrow(df) == 1e5`.
- [ ] Edit then Done: paint some bars, then type in a field and click Done
      directly, without Enter or a click elsewhere. Sample size `37`:
      `nrow(df) == 37`. Number of bins `5`: `dcr_spec(df)$nbins == 5`.
      Variables `V1, V2` (V2 empty): `V2` is dropped with the warning.
- [ ] Remove a variable that has bars (e.g. `A, B` to `A`): the message "B
      removed - Ctrl+Z to undo" shows in the canvas; `Ctrl+Z` brings it back.
- [ ] Two variables where the second is left all-zero: Done returns a data
      frame with only the first column and a warning naming the dropped
      variable. Nothing drawn at all: "Nothing to return yet", gadget stays
      open.
- [ ] Release the pointer outside the window mid-drag: the drag ends and the
      next press starts a new one.
- [ ] Done via *Addins > DataCraftR > Histogram* inserts the code; running it
      reproduces the same data.
- [ ] Cancel (button and `Esc` outside a field) returns `NULL`.

## Density

- [ ] Open `dcr_density(xlim = c(10, 20))`: one Bell curve (peak 0.85) centred
      at 15 spans exactly 10 to 20 with its filled area; the Y axis is titled
      "relative density" (0 to 1). Moving the pointer over the plot shows a
      dashed falloff curve and a faint vertical line under the cursor.
- [ ] Pull (default): press on the curve and drag up or down: the part around
      the press point rises or falls like cloth, the x of the press stays
      fixed, the curve never leaves 0 to 1 and both ends stay at 0. Releasing
      and pressing again starts from the new shape.
- [ ] Paint: press and move: the curve moves towards the cursor height while
      you move, around where you pass. Holding still does nothing until the
      next move. A press that moves less than 3 px changes nothing (Pull too).
- [ ] Switch Pull and Paint mid-session (between strokes, several times) and
      keep editing; nothing gets stuck and each stroke follows the selected mode.
- [ ] Brush width: the slider, and `[` / `]` (divide / multiply by 1.2), change
      the falloff preview and the slider together; extreme values (slider at
      both ends, holding `[` or `]`) never break the curve.
- [ ] Add variables (`dcr_density(c("A", "B", "C"))`): inactive variables show
      as faint dashed outlines, the active one is filled; keys `1`-`3` or the
      buttons switch the active variable; only the active one is edited.
- [ ] Bell, Flat and Skewed replace the active variable's curve (Flat = 0.5,
      Skewed has a long right tail); each is one undo step and repeating one
      adds nothing. The toolbar Clear puts every variable back to a Bell and
      keeps names, x range and n.
- [ ] One drag = one undo step (`Ctrl+Z` undoes the whole drag, `Ctrl+Shift+Z`
      redoes it).
- [ ] Change the x range after drawing (e.g. 10-20 to 0-30): the curve keeps
      its place on the axis, is 0 outside the old range and the brush width
      scales with the new range; undo restores it. A range that does not
      overlap the old one empties the curves: Done says "Nothing to return
      yet".
- [ ] Variables: add `D` (new Bell, others untouched); rename `V2` to `X`
      (curve kept); remove a shaped one: the message "B removed - Ctrl+Z to
      undo" shows in the canvas. Invalid (`A, A`, empty, 11 names):
      notification, no change.
- [ ] Rapid repeated clicks and drags never freeze: click 50 times quickly on
      the plot in both modes (clicks without movement add no undo steps), then
      drag fast in circles in both modes; the tool stays responsive and
      `Ctrl+Z` steps back through only the real drags.
- [ ] Edit then Done: draw something, then type in a field and click Done
      directly, without Enter or a click elsewhere. Sample size `37`:
      `nrow(df) == 37`; a new x range is applied.
- [ ] Done from the console returns `n` rows per variable, all inside `xlim`;
      a variable whose curve was emptied is dropped with a warning.
- [ ] Done via *Addins > DataCraftR > Density* inserts three lines (spec,
      seed, load code) and `dcr_load()` of the inserted id reproduces the same
      data.
- [ ] Cancel (button and `Esc` outside a field) returns `NULL`.

## Bivariate

- [ ] Open `dcr_bivariate()`: two groups (A top, B below right of the centre),
      each a solid 1-sigma and a lighter 2-sigma ellipse in its palette colour;
      the active group (A) shows a centre dot, a major handle and a minor
      handle joined to the centre by dashed lines. Axes 0 to 10 with equal
      pixels per unit, titles "x" and "y". The stats table shows the means,
      sds and r of each group and of "All".
- [ ] Handles feel: drag the centre (the ellipse follows, the mean stops at the
      plot edge); drag the major handle outwards and inwards (sd along the axis
      changes, the other does not); drag the minor handle both ways; rotate by
      dragging the major handle round the centre, past 180 degrees and several
      turns, with no jump at the grab and no flip of the axes. Pulling a handle
      through the centre never gives a zero or negative sd (it stops at a tiny
      minimum and mirrors past it).
- [ ] Click inside another group's 2-sigma ellipse: it becomes the active group
      (sidebar buttons follow) and nothing is added to the undo history.
      Keys `1`-`2` do the same.
- [ ] One drag = one undo step; `Ctrl+Z` undoes the whole drag (axes growth
      included), `Ctrl+Shift+Z` redoes it.
- [ ] Rapid repeated clicks and drags never freeze: click 50 times quickly on
      the centre, on each handle, on the ring and on empty canvas (clicks add
      no undo steps), then drag fast in circles on each handle; the tool stays
      responsive and `Ctrl+Z` steps back through only the real drags.
- [ ] Fit axes automatically (default on): drag a group to the edge of the plot
      or stretch it past the frame: on release the axes grow to hold every
      group's 2-sigma box (rounded ends, never shrinking) and the sidebar
      ranges follow. Turn it off: the axes stay and the ellipse is clipped.
- [ ] Type an x range that hides a group (e.g. 50 to 60 with the groups near
      5): the axes expand to keep every group in view and the message "Axes
      expanded to keep every group in view" shows; one undo step. Reset axes
      returns to the initial limits (expanding again if a mean is outside, with
      the message), and does nothing when already there.
- [ ] Groups: add `C` (appears at the view centre, small, rho 0, others
      untouched); rename `B` to `Z` (ellipse kept); remove one: the message "A
      removed - Ctrl+Z to undo" shows in the canvas. Invalid (`A, A`, empty, 11
      names): notification, no change. Clear puts every group back on the
      initial layout (undoable) and keeps names, n and the axes.
- [ ] `dcr_bivariate(c("A", "B", "C"), n = 4e5)` errors before opening;
      `n = 0` errors; in the sidebar a sample size that would exceed 1e6 rows
      is ignored. Modes: "Gestures" is accepted and behaves like "Handles"
      for now.
- [ ] Edit then Done: drag something, then type in a field (e.g. sample size
      `37`) and click Done directly, without Enter or a click elsewhere.
      `nrow(df) == 37 * 2` and the new value is applied.
- [ ] Done from the console returns `n` rows per group with the group factor
      levels in order; the column names follow the Names fields.
- [ ] Done via *Addins > DataCraftR > Bivariate normal* inserts three lines
      (spec, seed, load code) and `dcr_load()` of the inserted id reproduces
      the same data.
- [ ] Cancel (button and `Esc` outside a field) returns `NULL`.

## Count

- [ ] Open `dcr_count(c("A", "B"), c("x", "y", "z"), ymax = 20)`: categories on
      the X axis, one bar per variable inside each category (palette colours,
      legend on top), every bar at 5 with its count above it; the Y axis has
      whole-number ticks and is titled "count".
- [ ] Press and drag across the bars: each bar under the pointer jumps to the
      pointer's height, snapped to a whole number. A very fast sweep leaves no
      gaps (skipped bars are interpolated). Dragging outside the frame clamps
      to the first/last bar and to 0 and Y max.
- [ ] One drag = one undo step (`Ctrl+Z` undoes the whole drag, `Ctrl+Shift+Z`
      redoes it). Keys `1`-`2` only highlight a variable (bolder bars and
      legend entry).
- [ ] Align top / middle / bottom set every bar to Y max / half of it / 0; each
      is one undo step, and repeating one adds nothing.
- [ ] Y max below a drawn count (e.g. bars at 12, Y max 5): the axis goes back
      to 12, the field shows 12 and the notice "Y max raised to 12 to keep
      your counts" appears; no bar is cut. Y max 0, 2.5: notification, no
      change.
- [ ] Rename a variable or category: bars kept. Add one: it starts at 0, the
      others untouched. Remove one: the others keep their bars. Invalid (`A, A`,
      empty, 11 names): notification, no change. `Ctrl+Z` undoes each.
- [ ] Remove a variable or category that has counts: the message "N
      observations of B removed - Ctrl+Z to undo" shows in the canvas.
- [ ] Edit then Done: type in a field and click Done directly, without Enter
      or a click elsewhere. Variables `A, B, C`: `levels(df$variable)` has C
      (with no rows). Categories `x, y`: z is gone from `df`. Y max `40`:
      no error, the drawn counts are returned.
- [ ] Stats table: one row per (variable, category) plus a Total row per
      variable, the category totals and the grand total; `prop_of_total`
      of the non-total rows sums to 1.
- [ ] Clear (toolbar) zeroes every bar and keeps names and Y max.
- [ ] Done returns exactly what was drawn: `table(df)` matches the bar heights
      (rows = variable, columns = category, in the drawn order); factor levels
      follow the drawn order. All bars at 0: "Nothing to return yet", gadget
      stays open.
- [ ] Done via *Addins > DataCraftR > Count* inserts the code; running it
      reproduces the same data. Cancel (button and `Esc` outside a field)
      returns `NULL`.
- [ ] Total cap: with `dcr_count(ymax = 1e6)` and 10 variables x 10 categories,
      Align top sets each bar to 10000 (total 1e6) and shows the notice "Total
      capped at 1e6 observations"; painting stops growing once the total hits
      1e6. Done returns without hanging.

## RStudio integration

Run these in RStudio itself (they cannot be checked from the console tests).

- [ ] The gadget opens in the RStudio dialog viewer (not only in a browser):
      `dcr_scatter()` from the RStudio console opens a 1000 x 720 dialog;
      drawing, keyboard shortcuts, Done and Cancel work there; closing the
      dialog with its window button returns `NULL`.
- [ ] Addin with no document open (close every source tab), then
      *Addins > DataCraftR > Scatter*, draw, Done: the three lines are sent
      to the console and run after the gadget has returned (the console is
      busy while the gadget is open); `df` then exists in the session.
- [ ] Addin in an `.Rmd` and in a `.qmd`, cursor in prose (outside any
      chunk): the code is inserted on the next line wrapped in a new
      ```` ```{r} ```` chunk.
- [ ] Same, cursor inside an existing `{r}` chunk: the code is inserted on
      the next line without a new chunk.
- [ ] Same, with a plain ```` ``` ```` or ```` ```bash ```` block above the
      cursor (cursor in prose after it): the code is wrapped in a new chunk,
      not nested inside another one.
- [ ] Cursor on the last line of a file that has no trailing newline (e.g.
      `x <- 1` typed at the very end): the code starts on a new line below,
      `x <- 1` is unchanged and the file runs.
- [ ] Scatter stats: the last row "All" shows n, means, sds and r over every
      point.
