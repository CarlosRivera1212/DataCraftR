## Submission

This is an update from 0.3.2 to 0.5.6. The package was rebuilt on a shared
engine (0.4.0) and five drawing tools were added (density, bivariate normal,
mosaic, regression curve, radar). See NEWS.md.

The old functions `scatter_dcr()`, `boxplot_dcr()`, `histogram_dcr()` and
`count_dcr()` are deprecated, not removed. They now return the data frame
instead of writing a temporary file.

## Test environments

* Windows 11, R 4.5.2 (local)
* win-builder: Windows, R-devel (2026-11-17 r90926 ucrt)

## R CMD check results

Local (R 4.5.2): 0 errors | 0 warnings | 0 relevant notes. The only notes come
from the local machine (no LaTeX or pandoc installed, and "unable to verify
current time").

win-builder (R-devel): Status OK, with no errors, warnings or notes.
