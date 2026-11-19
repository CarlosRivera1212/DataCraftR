hs <- function(weights, variables = "V1", xlim = c(0, 2), nbins = length(weights)) {
  as_dcr_spec(list(tool = "histogram", variables = variables, xlim = xlim,
                   nbins = nbins, weights = weights, n = 100))
}

test_that("xmin is respected", {
  spec <- hs(c(0, 0, 1, 0, 0), xlim = c(10, 20))
  df <- dcr_sample(spec, n = 1000, seed = 1)
  expect_true(all(df$V1 >= 14 & df$V1 <= 16))
})

test_that("bin proportions follow the weights", {
  df <- dcr_sample(hs(c(1, 3)), n = 1e5, seed = 1)
  expect_lt(abs(mean(df$V1 >= 1) - 0.75), 0.01)
})

test_that("all-zero variables are dropped and reported", {
  spec <- hs(rbind(c(1, 1), c(0, 0)), variables = c("V1", "V2"), nbins = 2)
  df <- dcr_sample(spec, n = 20, seed = 1)
  expect_equal(ncol(df), 1L)
  expect_equal(attr(df, "dropped"), "V2")
  expect_false(spec_is_empty(spec))
  expect_true(spec_is_empty(hs(c(0, 0))))
})

test_that("spec_stats matches the bin mixture", {
  st <- spec_stats(hs(c(1, 1)))
  expect_equal(st$mean, 1)
  expect_equal(st$sd, sqrt(1 / 3))
  expect_equal(st$median, 1)
  expect_equal(nrow(st), 1L)
})

test_that("validation rejects bad input", {
  expect_error(hs(rep(1, 101), nbins = 101), "nbins")
  expect_error(hs(c(1, -1)), "non-negative")
  expect_error(hs(c(1, 1, 1), nbins = 2), "weights")
  expect_error(hs(c(1, 1), xlim = c(5, 5)), "xlim")
  expect_equal(spec_kind(hs(c(1, 1))), "population")
  expect_equal(spec_n(hs(c(1, 1))), 100)
})

test_that("a missing n is not taken from nbins (no partial matching)", {
  spec <- as_dcr_spec(list(tool = "histogram", variables = "V1", xlim = c(0, 1),
                           nbins = 5, weights = rep(1, 5)))
  expect_null(spec[["n"]])
  expect_null(spec[["seed"]])
})
