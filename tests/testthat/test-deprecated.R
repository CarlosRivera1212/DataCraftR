test_that("old names warn and return the gadget value", {
  demo <- data.frame(x = 1:3)
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    expect_s3_class(tool, "dcr_tool")
    expect_identical(mode, "addin")
    demo
  })
  old <- list(scatter_dcr = "dcr_scatter", boxplot_dcr = "dcr_boxplot",
              histogram_dcr = "dcr_histogram", count_dcr = "dcr_count")
  for (nm in names(old)) {
    f <- get(nm, envir = asNamespace("DataCraftR"))
    expect_warning(res <- withVisible(f()), old[[nm]])
    expect_identical(res$value, demo)
    expect_false(res$visible)
  }
})
