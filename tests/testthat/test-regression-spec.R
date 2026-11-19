K <- 201
xs_grid <- seq(0, 10, length.out = K)

rg <- function(...) {
  args <- list(tool = "regression", groups = c("A", "B"),
               names = list(x = "x", y = "y", group = "group"),
               xlim = c(0, 10),
               f = rbind(xs_grid, 10 - xs_grid),
               s = matrix(1, 2, K), n = 50, shared_x = TRUE)
  over <- list(...)
  args[names(over)] <- over
  as_dcr_spec(args)
}

one <- function(f, s, ...) {
  rg(groups = "A", f = matrix(f, 1), s = matrix(s, 1), ...)
}

test_that("shared x is reused across groups", {
  df <- dcr_sample(rg(), n = 100, seed = 1)
  expect_equal(nrow(df), 200)
  expect_equal(names(df), c("x", "y", "group"))
  expect_equal(levels(df$group), c("A", "B"))
  expect_true(all(df$group[1:100] == "A"))
  expect_equal(df$x[1:100], df$x[101:200])
  expect_equal(spec_n(rg()), 100)
  expect_false(spec_is_empty(rg()))
  expect_equal(spec_kind(rg()), "population")
})

test_that("unshared x differs per group", {
  df <- dcr_sample(rg(shared_x = FALSE), n = 100, seed = 1)
  expect_false(isTRUE(all.equal(df$x[1:100], df$x[101:200])))
})

test_that("one group as plain vectors is accepted", {
  spec <- as_dcr_spec(list(tool = "regression", groups = "A",
                           names = list(x = "x", y = "y", group = "group"),
                           xlim = c(0, 10), f = xs_grid, s = rep(1, K),
                           n = 10))
  expect_equal(dim(spec$f), c(1L, K))
  expect_true(spec$shared_x)
})

test_that("n times groups is capped", {
  expect_error(rg(n = 4e5, groups = c("A", "B", "C"),
                  f = matrix(1, 3, K), s = matrix(1, 3, K)),
               "times the number of groups")
})

test_that("linear curve with constant error recovers lm", {
  df <- dcr_sample(one(2 + 3 * xs_grid, rep(1, K)), n = 2e5, seed = 2)
  fit <- stats::lm(y ~ x, df)
  expect_lt(max(abs(stats::coef(fit) - c(2, 3))), 0.02)
  expect_lt(abs(stats::sigma(fit) - 1), 0.01)
})

test_that("cone error follows the analytic sd", {
  s <- 0.1 + 0.9 * xs_grid / 10
  df <- dcr_sample(one(rep(0, K), s), n = 2e5, seed = 3)
  lo <- df$y[df$x < 1]
  hi <- df$y[df$x > 9]
  expect_equal(stats::sd(lo), 0.1 + 0.9 * 0.05, tolerance = 0.1)
  expect_equal(stats::sd(hi), 0.1 + 0.9 * 0.95, tolerance = 0.1)
})

test_that("seeds and custom names", {
  a <- dcr_sample(rg(), n = 20, seed = 5)
  b <- dcr_sample(rg(), n = 20, seed = 5)
  expect_identical(a, b)
  d <- dcr_sample(rg(names = list(x = "h", y = "w", group = "g")), n = 5, seed = 1)
  expect_equal(names(d), c("h", "w", "g"))
})

test_that("stats match closed form and simulation", {
  spec <- one(2 + 3 * xs_grid, rep(1, K))
  st <- spec_stats(spec)
  expect_equal(names(st), c("group", "mean_x", "sd_x", "mean_y", "sd_y",
                            "r", "r2_curve"))
  expect_equal(st$r2_curve, 75 / 76, tolerance = 1e-4)
  expect_equal(st$mean_x, 5)
  expect_equal(st$sd_x, 10 / sqrt(12), tolerance = 1e-8)
  df <- dcr_sample(spec, n = 2e5, seed = 4)
  expect_lt(abs(st$mean_y - mean(df$y)), 0.05)
  expect_lt(abs(st$sd_y - stats::sd(df$y)), 0.05)
  expect_lt(abs(st$r - stats::cor(df$x, df$y)), 0.01)
  expect_equal(nrow(spec_stats(rg())), 2)
})

test_that("zero error and constant curves", {
  spec <- one(2 + 3 * xs_grid, rep(0, K))
  df <- dcr_sample(spec, n = 100, seed = 1)
  expect_equal(df$y, 2 + 3 * df$x, tolerance = 1e-8)
  st <- spec_stats(one(rep(4, K), rep(0, K)))
  expect_true(is.na(st$r))
  expect_true(is.na(st$r2_curve))
  df0 <- dcr_sample(one(rep(4, K), rep(0, K)), n = 10, seed = 1)
  expect_true(all(df0$y == 4))
  # constant f with error: r is 0, r2_curve 0
  st2 <- spec_stats(one(rep(4, K), rep(1, K)))
  expect_equal(st2$r2_curve, 0, tolerance = 1e-8)
})

test_that("validation errors", {
  expect_error(rg(groups = "A", f = matrix(1, 1, 2), s = matrix(1, 1, 2)), "grid")
  f <- rbind(xs_grid, 10 - xs_grid)
  f[1, 3] <- NaN
  expect_error(rg(f = f), "finite")
  s <- matrix(1, 2, K)
  s[2, 5] <- -0.1
  expect_error(rg(s = s), "non-negative")
  expect_error(rg(s = matrix(1, 2, K - 1)), "same dimensions")
  expect_error(rg(f = matrix(1, 3, K)), "one row per group")
  expect_error(rg(n = 0), "whole number")
  expect_error(rg(xlim = c(5, 5)), "xlim")
  expect_error(rg(groups = c("A", "A")), "unique")
  expect_error(rg(shared_x = "yes"), "shared_x")
  expect_error(rg(names = list(x = "a", y = "a", group = "g")), "unique")
})
