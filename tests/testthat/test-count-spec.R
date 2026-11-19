ct <- function(counts, variables = c("v1", "v2"), categories = c("a", "b", "c")) {
  as_dcr_spec(list(tool = "count", variables = variables, categories = categories,
                   counts = counts))
}

test_that("count expands to long data frame matching the matrix", {
  m <- rbind(c(2, 0, 1), c(1, 1, 1))
  spec <- ct(m)
  df <- dcr_sample(spec)
  expect_equal(nrow(df), 6L)
  expect_equal(names(df), c("variable", "category"))
  expect_equal(levels(df$category), c("a", "b", "c"))
  tb <- table(df)
  expect_equal(unname(unclass(tb)), unname(m), ignore_attr = TRUE)
  expect_equal(dimnames(tb), list(variable = c("v1", "v2"), category = c("a", "b", "c")))
  expect_equal(spec_n(spec), 6L)
  expect_equal(spec_kind(spec), "literal")
  expect_true(is.integer(spec$counts))
})

test_that("count stats", {
  st <- spec_stats(ct(rbind(c(2, 0, 2), c(1, 1, 1))))
  # (2 variables + Total) x (3 categories + Total)
  expect_equal(nrow(st), 12L)
  expect_equal(names(st), c("variable", "category", "count", "prop_in_variable",
                            "prop_of_total"))
  expect_equal(st$prop_in_variable[1:3], c(.5, 0, .5))
  # per-variable totals
  tv <- st[st$category == "Total" & st$variable != "Total", ]
  expect_equal(tv$variable, c("v1", "v2"))
  expect_equal(tv$count, c(4, 3))
  expect_equal(tv$prop_in_variable, c(1, 1))
  expect_equal(tv$prop_of_total, c(4, 3) / 7)
  # per-category totals and the grand total
  tc <- st[st$variable == "Total", ]
  expect_equal(tc$category, c("a", "b", "c", "Total"))
  expect_equal(tc$count, c(3, 1, 3, 7))
  expect_equal(tc$prop_in_variable, c(3, 1, 3, 7) / 7)
  expect_equal(sum(st$prop_of_total[st$variable != "Total" & st$category != "Total"]), 1)
})

test_that("count stats with all zeros are NA, not NaN", {
  st <- spec_stats(ct(rbind(c(0, 0, 0), c(0, 0, 0))))
  expect_true(all(is.na(st$prop_in_variable)))
  expect_true(all(is.na(st$prop_of_total)))
  expect_false(any(is.nan(st$prop_of_total)))
})

test_that("count validation", {
  expect_error(ct(rbind(c(-1, 0, 1), c(1, 1, 1))), "whole numbers")
  expect_error(ct(rbind(c(1.5, 0, 1), c(1, 1, 1))), "whole numbers")
  expect_error(ct(rbind(c(1, 0), c(1, 1))), "dimensions")
  expect_error(ct(rbind(c(1, 0, 1)), variables = c("v1", "v2")), "dimensions")
})

test_that("vectors coerce when one variable or one category", {
  expect_equal(dim(ct(c(1, 2, 3), variables = "v")$counts), c(1L, 3L))
  expect_equal(dim(ct(c(1, 2), categories = "a")$counts), c(2L, 1L))
  expect_true(spec_is_empty(ct(c(0, 0, 0), variables = "v")))
  expect_equal(nrow(dcr_sample(ct(c(0, 0, 0), variables = "v"))), 0L)
})

test_that("count specs with more than 1e6 observations are rejected", {
  big <- list(tool = "count", variables = c("A", "B"), categories = "x",
              counts = list(1e6, 1))
  expect_error(as_dcr_spec(big), "at most 1e6")
  ok <- big
  ok$counts <- list(5e5, 5e5)
  expect_s3_class(as_dcr_spec(ok), "dcr_spec")
})
