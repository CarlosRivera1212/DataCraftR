bx <- function(family = "normal", variables = "V1", q1 = 2, q2 = 3, q3 = 5, ...) {
  as_dcr_spec(list(tool = "boxplot", family = family, variables = variables,
                   q1 = q1, q2 = q2, q3 = q3, ylim = c(0, 10), n = 100, ...))
}

test_that("qtwopiece reproduces exact quartiles", {
  for (f in c("normal", "uniform")) {
    expect_equal(qtwopiece(c(.25, .5, .75), 2, 3, 5, f), c(2, 3, 5))
  }
})

test_that("sample quartiles match the spec", {
  for (f in c("normal", "uniform")) {
    df <- dcr_sample(bx(f), n = 2e5, seed = 1)
    qs <- unname(stats::quantile(df$V1, c(.25, .5, .75)))
    expect_true(all(abs(qs - c(2, 3, 5)) < 0.02))
  }
})

test_that("spec_stats mean and sd match simulation for asymmetric case", {
  for (f in c("normal", "uniform")) {
    spec <- bx(f)
    df <- dcr_sample(spec, n = 2e5, seed = 2)
    st <- spec_stats(spec)
    expect_lt(abs(mean(df$V1) - st$mean), 0.02)
    expect_lt(abs(stats::sd(df$V1) - st$sd), 0.02)
    expect_equal(st$iqr, 3)
  }
})

test_that("invalid quartiles and ranges are rejected", {
  expect_error(bx(q1 = 3, q2 = 2), "q1 < q2 < q3")
  expect_error(as_dcr_spec(list(tool = "boxplot", family = "normal",
                                variables = "V1", q1 = 2, q2 = 3, q3 = 5,
                                ylim = c(5, 5))), "ylim")
  expect_error(bx(family = "cauchy"), "family")
  expect_error(bx(variables = c("a", "a"), q1 = c(1, 1), q2 = c(2, 2), q3 = c(3, 3)),
               "unique")
})

test_that("output columns follow variable names", {
  spec <- bx(variables = c("V1", "my var"), q1 = c(1, 2), q2 = c(2, 3), q3 = c(3, 5))
  df <- dcr_sample(spec, n = 50, seed = 1)
  expect_equal(names(df), c("V1", "my var"))
  expect_equal(nrow(df), 50L)
  expect_false(spec_is_empty(spec))
  expect_equal(spec_kind(spec), "population")
  expect_equal(spec_n(spec), 100)
})
