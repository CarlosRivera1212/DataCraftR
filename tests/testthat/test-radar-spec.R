rd <- function(...) {
  args <- list(tool = "radar", groups = c("A", "B"),
               variables = c("v1", "v2", "v3", "v4"),
               ranges = list(c(0, 10), c(-5, 5), c(100, 200), c(0, 1)),
               mean = list(c(4, 0, 150, 0.5), c(7, 2, 120, 0.3)),
               sd = list(c(1, 1, 15, 0.1), c(2, 0.5, 10, 0.2)),
               n = 200, integers = FALSE, group_name = "group")
  over <- list(...)
  args[names(over)] <- over
  as_dcr_spec(args)
}

test_that("sampler stays in range and matches the truncated moments", {
  spec <- rd()
  df <- dcr_sample(spec, n = 1e5, seed = 1)
  expect_equal(nrow(df), 2e5)
  expect_equal(names(df), c("group", "v1", "v2", "v3", "v4"))
  expect_equal(levels(df$group), c("A", "B"))
  expect_true(all(df$group[1:1e5] == "A"))
  expect_true(all(df$group[1e5 + 1:1e5] == "B"))
  st <- spec_stats(spec)
  expect_equal(names(st), c("group", "variable", "mean", "sd"))
  expect_equal(nrow(st), 8)
  for (j in 1:4) {
    r <- spec$ranges[j, ]
    w <- diff(r)
    v <- df[[spec$variables[j]]]
    expect_true(all(v >= r[1] & v <= r[2]))
    for (i in 1:2) {
      d <- v[df$group == spec$groups[i]]
      m <- tnorm_moments(spec$mean[i, j], spec$sd[i, j], r[1], r[2])
      expect_lt(abs(mean(d) - m[["mean"]]), 0.01 * w)
      expect_lt(abs(stats::sd(d) - m[["sd"]]), 0.01 * w)
      s <- st[st$group == spec$groups[i] & st$variable == spec$variables[j], ]
      expect_equal(s$mean, m[["mean"]])
      expect_equal(s$sd, m[["sd"]])
    }
  }
  expect_equal(spec_n(spec), 400)
  expect_false(spec_is_empty(spec))
  expect_equal(spec_kind(spec), "population")
})

test_that("mean at the range end with a wide sd stays inside (truncated)", {
  spec <- rd(groups = "A", ranges = rep(list(c(0, 10)), 4),
             mean = list(c(10, 10, 10, 10)), sd = list(rep(3, 4)))
  df <- dcr_sample(spec, n = 1e5, seed = 2)
  m <- tnorm_moments(10, 3, 0, 10)
  expect_lt(m[["mean"]], 10)
  for (v in spec$variables) {
    expect_true(all(df[[v]] >= 0 & df[[v]] <= 10))
    expect_lt(abs(mean(df[[v]]) - m[["mean"]]), 0.1)
    expect_lt(abs(stats::sd(df[[v]]) - m[["sd"]]), 0.1)
  }
  expect_equal(spec_stats(spec)$mean, rep(m[["mean"]], 4))
})

test_that("tnorm_moments matches a large simulation", {
  set.seed(3)
  for (p in list(c(2, 3, 0, 10), c(0, 2, 0, 10), c(9, 4, 0, 10),
                 c(30, 1, 0, 10), c(5, 0.2, 0, 10))) {
    x <- rtnorm_range(1e6, p[1], p[2], p[3], p[4])
    m <- tnorm_moments(p[1], p[2], p[3], p[4])
    expect_lt(abs(mean(x) - m[["mean"]]), 0.01)
    expect_lt(abs(stats::sd(x) - m[["sd"]]), 0.01)
  }
  expect_equal(tnorm_moments(4, 0, 0, 10), c(mean = 4, sd = 0))
  expect_equal(tnorm_moments(5, 1, 0, 10)[["mean"]], 5)
})

test_that("sd = 0 gives a constant column", {
  spec <- rd(sd = list(c(0, 1, 15, 0.1), c(0, 0.5, 10, 0.2)))
  df <- dcr_sample(spec, n = 50, seed = 1)
  expect_true(all(df$v1[df$group == "A"] == 4))
  expect_true(all(df$v1[df$group == "B"] == 7))
  expect_equal(rtnorm_range(5, 3, 0, 0, 10), rep(3, 5))
})

test_that("integers are whole numbers inside the range", {
  spec <- rd(integers = TRUE, mean = list(c(10, 0, 100, 1), c(0, 5, 200, 0)),
             sd = list(c(3, 3, 30, 1), c(3, 3, 30, 1)))
  df <- dcr_sample(spec, n = 2000, seed = 4)
  for (j in 1:4) {
    v <- df[[spec$variables[j]]]
    expect_true(all(v == round(v)))
    expect_true(all(v >= spec$ranges[j, 1] & v <= spec$ranges[j, 2]))
  }
})

test_that("seed reproducibility", {
  spec <- rd()
  a <- dcr_sample(spec, n = 100, seed = 9)
  b <- dcr_sample(spec, n = 100, seed = 9)
  expect_identical(as.data.frame(a), as.data.frame(b))
  c2 <- dcr_sample(spec, n = 100, seed = 10)
  expect_false(identical(a$v1, c2$v1))
})

test_that("custom group_name and variable names are used", {
  spec <- rd(group_name = "arm", variables = c(" a ", "b", "c d"),
             ranges = rep(list(c(0, 1)), 3),
             mean = list(rep(0.5, 3), rep(0.5, 3)),
             sd = list(rep(0.1, 3), rep(0.1, 3)))
  df <- dcr_sample(spec, n = 5, seed = 1)
  expect_equal(names(df), c("arm", "a", "b", "c d"))
})

test_that("one group x three variables sent as flat vectors is accepted", {
  spec <- rd(groups = "A", variables = c("x", "y", "z"),
             ranges = c(0, 10, 0, 10, 0, 10), mean = c(5, 5, 5),
             sd = c(1, 1, 1))
  expect_equal(dim(spec$mean), c(1L, 3L))
  expect_equal(dim(spec$ranges), c(3L, 2L))
  expect_equal(dim(dcr_sample(spec, n = 10, seed = 1)), c(10L, 4L))
  spec2 <- rd(groups = list("A"), variables = list("x", "y", "z"),
              ranges = list(list(0, 10), list(0, 10), list(0, 10)),
              mean = list(list(5, 5, 5)), sd = list(list(1, 1, 1)))
  expect_equal(spec2$mean, spec$mean)
  expect_equal(spec2$ranges, spec$ranges)
})

test_that("validation errors", {
  expect_error(rd(variables = c("a", "b"), ranges = list(c(0, 1), c(0, 1)),
                  mean = list(c(0, 0), c(0, 0)), sd = list(c(1, 1), c(1, 1))),
               "variables")
  v13 <- paste0("v", 1:13)
  expect_error(rd(variables = v13, ranges = rep(list(c(0, 1)), 13),
                  mean = list(rep(0.5, 13), rep(0.5, 13)),
                  sd = list(rep(0.1, 13), rep(0.1, 13))), "variables")
  v12 <- paste0("v", 1:12)
  ok <- rd(variables = v12, ranges = rep(list(c(0, 1)), 12),
           mean = list(rep(0.5, 12), rep(0.5, 12)),
           sd = list(rep(0.1, 12), rep(0.1, 12)))
  expect_equal(ncol(ok$mean), 12L)
  expect_error(rd(variables = c("a", "a", "b", "c")), "unique")
  expect_error(rd(groups = LETTERS[1:11]), "groups")
  expect_error(rd(mean = list(c(11, 0, 150, 0.5), c(7, 2, 120, 0.3))), "range")
  expect_error(rd(mean = list(c(4, 0, 150, -0.5), c(7, 2, 120, 0.3))), "range")
  expect_error(rd(sd = list(c(-1, 1, 15, 0.1), c(2, 0.5, 10, 0.2))), "sd")
  expect_error(rd(sd = list(c(NA, 1, 15, 0.1), c(2, 0.5, 10, 0.2))), "sd")
  expect_error(rd(ranges = list(c(0, 10), c(5, -5), c(100, 200), c(0, 1))),
               "ranges")
  expect_error(rd(group_name = "v2"), "group_name")
  expect_error(rd(group_name = ""), "group_name")
  expect_error(rd(n = 4e5, groups = c("A", "B", "C"),
                  mean = list(c(4, 0, 150, 0.5), c(7, 2, 120, 0.3),
                              c(1, 1, 110, 0.1)),
                  sd = list(c(1, 1, 15, 0.1), c(2, 0.5, 10, 0.2),
                            c(1, 1, 1, 0.1))),
               "at most 1e6")
  expect_error(rd(n = 0), "whole number")
  expect_error(rd(n = 2.5), "whole number")
  expect_error(rd(n = 2e6), "whole number")
  expect_error(rd(integers = "yes"), "integers")
  expect_equal(rd(integers = NULL)$integers, FALSE)
  # ragged rows and wrong dimensions
  expect_error(rd(mean = list(c(4, 0, 150), c(7, 2, 120, 0.3))), "same length")
  expect_error(rd(mean = list(c(4, 0, 150, 0.5))), "one row per group")
  expect_error(rd(sd = list(c(1, 1, 15), c(2, 0.5, 10))), "variable")
  expect_error(rd(ranges = list(c(0, 10), c(-5, 5), c(100, 200))), "variable")
})
