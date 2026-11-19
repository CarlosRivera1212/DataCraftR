bv <- function(...) {
  args <- list(tool = "bivariate", groups = c("A", "B"),
               names = list(x = "x", y = "y", group = "group"),
               xlim = c(0, 10), ylim = c(0, 10),
               mean_x = c(2, 7), mean_y = c(3, 6),
               sd_x = c(1, 0.5), sd_y = c(0.5, 2),
               rho = c(0.8, -0.3), n = 200)
  over <- list(...)
  args[names(over)] <- over
  as_dcr_spec(args)
}

test_that("sampler matches the drawn parameters per group", {
  spec <- bv()
  df <- dcr_sample(spec, n = 1e5, seed = 1)
  expect_equal(nrow(df), 2e5)
  expect_equal(names(df), c("x", "y", "group"))
  expect_equal(levels(df$group), c("A", "B"))
  expect_true(all(df$group[1:1e5] == "A"))
  expect_true(all(df$group[1e5 + 1:1e5] == "B"))
  for (i in 1:2) {
    d <- df[df$group == c("A", "B")[i], ]
    expect_lt(abs((mean(d$x)) - (spec$mean_x[i])), 0.02)
    expect_lt(abs((mean(d$y)) - (spec$mean_y[i])), 0.02)
    expect_equal(stats::sd(d$x) / spec$sd_x[i], 1, tolerance = 0.02)
    expect_equal(stats::sd(d$y) / spec$sd_y[i], 1, tolerance = 0.02)
    expect_lt(abs((stats::cor(d$x, d$y)) - (spec$rho[i])), 0.01)
  }
  expect_equal(spec_n(spec), 400)
  expect_false(spec_is_empty(spec))
  expect_equal(spec_kind(spec), "population")
})

test_that("custom names, scalar single group and seeds", {
  df <- dcr_sample(bv(names = list(x = "height", y = "weight", group = "sex")),
                   n = 5, seed = 1)
  expect_equal(names(df), c("height", "weight", "sex"))
  one <- bv(groups = "A", mean_x = 2, mean_y = 3, sd_x = 1, sd_y = 1, rho = 0.5)
  d1 <- dcr_sample(one, n = 10, seed = 1)
  expect_true(is.factor(d1$group))
  expect_equal(nrow(d1), 10L)
  a <- dcr_sample(bv(), n = 20, seed = 3)
  expect_identical(a, dcr_sample(bv(), n = 20, seed = 3))
  expect_false(identical(a$x, dcr_sample(bv(), n = 20, seed = 4)$x))
})

test_that("spec_stats gives exact group rows and mixture row", {
  spec <- bv()
  st <- spec_stats(spec)
  expect_equal(st$group, c("A", "B", "All"))
  expect_equal(st$mean_x[1:2], c(2, 7), tolerance = 0)
  expect_equal(st$sd_y[1:2], c(0.5, 2), tolerance = 0)
  expect_equal(st$r[1:2], c(0.8, -0.3), tolerance = 0)
  mx <- c(2, 7); my <- c(3, 6); sx <- c(1, 0.5); sy <- c(0.5, 2); r <- c(0.8, -0.3)
  Mx <- 4.5; My <- 4.5
  Vx <- (sx[1]^2 + sx[2]^2 + (mx[1] - Mx)^2 + (mx[2] - Mx)^2) / 2
  Vy <- (sy[1]^2 + sy[2]^2 + (my[1] - My)^2 + (my[2] - My)^2) / 2
  C <- (r[1] * sx[1] * sy[1] + r[2] * sx[2] * sy[2] +
          (mx[1] - Mx) * (my[1] - My) + (mx[2] - Mx) * (my[2] - My)) / 2
  expect_equal(st$mean_x[3], Mx, tolerance = 1e-12)
  expect_equal(st$sd_x[3], sqrt(Vx), tolerance = 1e-12)
  expect_equal(st$sd_y[3], sqrt(Vy), tolerance = 1e-12)
  expect_equal(st$r[3], C / sqrt(Vx * Vy), tolerance = 1e-12)
  df <- dcr_sample(spec, n = 2e5, seed = 2)
  expect_lt(abs((mean(df$x)) - (st$mean_x[3])), 0.02)
  expect_lt(abs((mean(df$y)) - (st$mean_y[3])), 0.02)
  expect_lt(abs((stats::sd(df$x)) - (st$sd_x[3])), 0.02)
  expect_lt(abs((stats::sd(df$y)) - (st$sd_y[3])), 0.02)
  expect_lt(abs((stats::cor(df$x, df$y)) - (st$r[3])), 0.02)
})

test_that("extreme rho and the 1e6 total are handled quickly", {
  spec <- bv(rho = c(0.999, -0.999), n = 5e5)
  invisible(dcr_sample(spec, seed = 1))  # warm-up: first big allocation is slow
  el <- system.time(df <- dcr_sample(spec, seed = 1))["elapsed"]
  expect_lt(el, 2)
  expect_true(all(is.finite(df$x)) && all(is.finite(df$y)))
  expect_equal(nrow(df), 1e6)
  expect_lt(abs((stats::cor(df$x[df$group == "A"], df$y[df$group == "A"])) - (0.999)), 0.005)
  expect_lt(abs((stats::cor(df$x[df$group == "B"], df$y[df$group == "B"])) - (-0.999)), 0.005)
  expect_error(bv(groups = c("A", "B", "C"), mean_x = 1:3, mean_y = 1:3,
                  sd_x = rep(1, 3), sd_y = rep(1, 3), rho = rep(0, 3), n = 4e5),
               "1e6")
})

test_that("invalid parameters are rejected", {
  expect_error(bv(sd_x = c(0, 1)), "sd")
  expect_error(bv(sd_y = c(1, -1)), "sd")
  expect_error(bv(rho = c(1, 0)), "rho")
  expect_error(bv(rho = c(NaN, 0)), "rho")
  expect_error(bv(mean_x = 1), "mean_x")
  expect_error(bv(xlim = c(5, 5)), "xlim")
  expect_error(bv(n = 0), "n must")
  expect_error(bv(n = 2.5), "n must")
  expect_error(bv(groups = c("A", "A")), "unique")
  g11 <- LETTERS[1:11]
  expect_error(bv(groups = g11, mean_x = 1:11, mean_y = 1:11, sd_x = rep(1, 11),
                  sd_y = rep(1, 11), rho = rep(0, 11)), "groups")
  expect_error(bv(names = list(x = "a", y = "a", group = "g")), "unique")
})
