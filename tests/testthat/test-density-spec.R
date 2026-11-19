ds <- function(curves, variables = "V1", xlim = c(0, 2), n = 100) {
  as_dcr_spec(list(tool = "density", variables = variables, xlim = xlim,
                   curves = curves, n = n))
}
tri <- function() ds(rbind(c(0, 1, 0)))
bell_spec <- function(K = 201, xlim = c(0, 10)) {
  xs <- seq(xlim[1], xlim[2], length.out = K)
  y <- dnorm(xs, 5, 1.2)
  y <- y / max(y)
  y[c(1, K)] <- 0
  list(spec = ds(rbind(y), xlim = xlim), xs = xs, ys = y)
}

test_that("spec_stats is exact for a triangle", {
  st <- spec_stats(tri())
  expect_equal(st$mean, 1, tolerance = 1e-9)
  expect_equal(st$sd, sqrt(1 / 6), tolerance = 1e-9)
  expect_equal(st$median, 1, tolerance = 1e-9)
})

test_that("spec_stats matches fine numerical integration", {
  b <- bell_spec(K = 41)
  xf <- seq(0, 10, length.out = 400001)
  f <- approx(b$xs, b$ys, xf)$y
  dx <- diff(xf)[1]
  z <- sum(f) * dx
  mu <- sum(xf * f) * dx / z
  sdv <- sqrt(sum(xf^2 * f) * dx / z - mu^2)
  st <- spec_stats(b$spec)
  expect_equal(st$mean, mu, tolerance = 1e-6)
  expect_equal(st$sd, sdv, tolerance = 1e-6)
  # asymmetric curve with a non-zero xmin
  s2 <- ds(rbind(c(0, 0.2, 1, 0.5, 0)), xlim = c(3, 9))
  xs <- seq(3, 9, length.out = 5)
  f2 <- approx(xs, c(0, 0.2, 1, 0.5, 0), xf <- seq(3, 9, length.out = 600001))$y
  dx <- diff(xf)[1]
  z <- sum(f2) * dx
  mu <- sum(xf * f2) * dx / z
  sdv <- sqrt(sum(xf^2 * f2) * dx / z - mu^2)
  st2 <- spec_stats(s2)
  expect_equal(st2$mean, mu, tolerance = 1e-6)
  expect_equal(st2$sd, sdv, tolerance = 1e-6)
  cdf <- cumsum(f2) * dx / z
  expect_equal(st2$median, xf[which(cdf >= 0.5)[1]], tolerance = 1e-4)
})

test_that("triangle sample matches theory", {
  df <- dcr_sample(tri(), n = 2e5, seed = 1)
  expect_lt(abs(mean(df$V1) - 1), 0.01)
  q <- unname(quantile(df$V1, c(0.25, 0.75)))
  expect_lt(max(abs(q - c(sqrt(0.5), 2 - sqrt(0.5)))), 0.01)
})

test_that("bell sample matches qdensity_pl", {
  b <- bell_spec()
  df <- dcr_sample(b$spec, n = 2e5, seed = 1)
  q <- unname(quantile(df$V1, c(0.1, 0.5, 0.9)))
  expect_lt(max(abs(q - qdensity_pl(c(0.1, 0.5, 0.9), b$xs, b$ys))), 0.02)
})

test_that("seed is reproducible and recorded", {
  spec <- tri()
  a <- dcr_sample(spec, n = 50, seed = 3)
  b <- dcr_sample(spec, n = 50, seed = 3)
  expect_identical(a$V1, b$V1)
  expect_equal(dcr_spec(a)$seed, 3)
})

test_that("isolated spikes and ramps never give NaN or leave xlim", {
  for (cv in list(c(0, 0, 1, 0, 0), c(0, 0, 0, 1, 0), c(0, 1, 0, 0, 0))) {
    df <- dcr_sample(ds(rbind(cv), xlim = c(10, 20)), n = 1e4, seed = 1)
    expect_false(anyNA(df$V1))
    expect_true(all(is.finite(df$V1)))
    expect_true(all(df$V1 >= 10 & df$V1 <= 20))
  }
  df <- dcr_sample(ds(rbind(c(0, 0, 1, 0, 0)), xlim = c(0, 4)), n = 1e4, seed = 1)
  expect_true(all(df$V1 >= 1 & df$V1 <= 3))
  u <- qdensity_pl(c(0, 0.5, 1), seq(0, 4, length.out = 5), c(0, 0, 1, 0, 0))
  expect_true(all(is.finite(u)) && all(u >= 1 & u <= 3))
})

test_that("all-zero variables are dropped and reported", {
  spec <- ds(rbind(c(0, 1, 0), c(0, 0, 0)), variables = c("V1", "V2"))
  df <- dcr_sample(spec, n = 20, seed = 1)
  expect_equal(ncol(df), 1L)
  expect_equal(attr(df, "dropped"), "V2")
  expect_false(spec_is_empty(spec))
  expect_true(spec_is_empty(ds(rbind(c(0, 0, 0)))))
  expect_equal(spec_kind(spec), "population")
  expect_equal(spec_n(spec), 100)
  expect_true(is.na(spec_stats(spec)$mean[2]))
})

test_that("n = 1e6 samples in under 2 seconds", {
  b <- bell_spec()
  el <- system.time(df <- dcr_sample(b$spec, n = 1e6, seed = 1))["elapsed"]
  expect_lt(unname(el), 2)
  expect_equal(nrow(df), 1e6)
})

test_that("validation rejects bad input", {
  expect_error(ds(rbind(c(0, 0))), "curves")
  expect_error(ds(rbind(rep(0, 1002))), "curves")
  expect_error(ds(rbind(c(0, -1, 0))), "curves")
  expect_error(ds(rbind(c(0, 1, 0.3))), "curves")
  expect_error(ds(rbind(c(0, 1, 0)), xlim = c(5, 5)), "xlim")
  expect_error(ds(rbind(c(0, 1, 0)), n = 0), "\\bn\\b")
  expect_error(ds(rbind(c(0, 1, 0)), n = 2e6), "\\bn\\b")
  expect_error(ds(rbind(c(0, 1, 0), c(0, 1, 0)), variables = c("a", "a")),
               "variables")
  expect_error(ds(rbind(c(0, 1, 0)), variables = c("a", "b")), "curves")
})

test_that("a single variable sent as a plain vector is accepted", {
  spec <- ds(c(0, 1, 0))
  expect_equal(dim(spec$curves), c(1L, 3L))
})
