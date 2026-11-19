# shiny::testServer() attaches shiny; do it once here, muffling only the
# local "built under R version" notice so test output stays clean.
withCallingHandlers(
  library(shiny, quietly = TRUE, warn.conflicts = FALSE),
  warning = function(w) {
    if (grepl("was built under R version", conditionMessage(w))) {
      invokeRestart("muffleWarning")
    }
  }
)

# Minimal tool and literal specs for the gadget shell tests.
helper_tool <- function() {
  new_dcr_tool("scatter", title = "Scatter",
               sidebar = function(options) shiny::tagList(),
               controls = character(), options = list())
}

helper_empty_scatter <- function() {
  as_dcr_spec(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                   groups = c("A", "B"),
                   points = list(x = numeric(0), y = numeric(0),
                                 group = character(0))))
}

helper_scatter <- function() {
  as_dcr_spec(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                   groups = c("A", "B"),
                   points = list(x = c(1, 2, 3), y = c(4, 5, 6),
                                 group = c("A", "A", "B"))))
}

# Population spec: the seed is recorded only for population tools.
helper_histogram <- function(weights = rbind(c(1, 2), c(1, 1))) {
  as_dcr_spec(list(tool = "histogram", variables = c("V1", "V2"),
                   xlim = c(0, 2), nbins = 2L, weights = weights, n = 10))
}
