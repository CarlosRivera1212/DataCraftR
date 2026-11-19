sc_code_spec <- function() {
  s <- as_dcr_spec(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                        groups = c("A", "B"),
                        points = list(x = c(1, 2, 3), y = c(4, 5, 6),
                                      group = c("A", "B", "A"))))
  s$created <- "2026-11-17T15:30:12Z"
  s
}

test_that("dcr_code gives the exact 3 lines for a literal spec", {
  withr::local_timezone("UTC")
  expect_identical(
    dcr_code("scatter_20261117_153012", sc_code_spec()),
    c("# DataCraftR \u00b7 scatter \u00b7 2026-11-17 15:30 \u00b7 n = 3",
      "df <- dcr_load(\"scatter_20261117_153012\")",
      "# write.csv(df, \"scatter.csv\", row.names = FALSE)   # save into your project")
  )
})

test_that("dcr_code includes the seed for a population spec", {
  withr::local_timezone("UTC")
  s <- as_dcr_spec(list(tool = "boxplot", family = "normal", variables = "V1",
                        q1 = 2, q2 = 3, q3 = 5, ylim = c(0, 10), n = 50))
  s$created <- "2026-11-17T15:30:12Z"
  s$seed <- 42L
  expect_identical(
    dcr_code("boxplot_20261117_153012", s),
    c("# DataCraftR \u00b7 boxplot \u00b7 2026-11-17 15:30 \u00b7 n = 50",
      "df <- dcr_load(\"boxplot_20261117_153012\", seed = 42)",
      "# write.csv(df, \"boxplot.csv\", row.names = FALSE)   # save into your project")
  )
})

test_that("dcr_code shows the created time in local time", {
  withr::local_timezone("America/New_York")
  expect_match(dcr_code("scatter_x", sc_code_spec())[1], "2026-11-17 10:30")
})
