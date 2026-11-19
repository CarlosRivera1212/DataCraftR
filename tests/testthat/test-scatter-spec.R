sc <- function(points, groups = c("A", "B", "C"), ...) {
  as_dcr_spec(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                   groups = groups, points = points, ...))
}

test_that("scatter round trip keeps points and all group levels", {
  spec <- sc(list(x = c(1, 2, 3), y = c(4, 5, 6), group = c("B", "A", "A")))
  df <- dcr_sample(spec)
  expect_equal(names(df), c("x", "y", "group"))
  expect_equal(levels(df$group), c("A", "B", "C"))
  expect_equal(df$x, c(2, 3, 1))
  expect_equal(df$y, c(5, 6, 4))
  expect_equal(spec_n(spec), 3L)
  expect_false(spec_is_empty(spec))
  expect_equal(spec_kind(spec), "literal")
})

test_that("custom names are used", {
  spec <- sc(list(x = 1, y = 2, group = "A"),
             names = list(x = "height", y = "weight", group = "species"))
  expect_equal(names(dcr_sample(spec)), c("height", "weight", "species"))
  expect_error(sc(list(x = 1, y = 2, group = "A"),
                  names = list(x = "a", y = "a", group = "g")), "unique")
})

test_that("unknown group label errors", {
  expect_error(sc(list(x = 1, y = 2, group = "Z")), "groups")
})

test_that("empty points give a 0-row data frame", {
  for (p in list(list(), list(x = numeric(0), y = numeric(0), group = character(0)),
                 list(x = list(), y = list(), group = list()))) {
    spec <- sc(p)
    expect_true(spec_is_empty(spec))
    df <- dcr_sample(spec)
    expect_equal(nrow(df), 0L)
    expect_equal(levels(df$group), c("A", "B", "C"))
    expect_equal(nrow(spec_stats(spec)), 4L)   # 3 groups + All
  }
})

test_that("spec_stats is NA-safe for small groups", {
  spec <- sc(list(x = c(1, 2, 3, 5), y = c(1, 2, 3, 2), group = c("A", "A", "A", "B")))
  expect_no_warning(st <- spec_stats(spec))
  expect_equal(st$n, c(3L, 1L, 0L, 4L))
  expect_equal(st$r[1], 1)
  expect_true(all(is.na(st$r[2:3])))
  expect_true(all(is.na(st$sd_x[2:3])))
  expect_equal(st$mean_x[1], 2)
})

test_that("spec_stats ends with an All row over every point", {
  spec <- sc(list(x = c(1, 2, 3, 5), y = c(1, 2, 3, 2), group = c("A", "A", "A", "B")))
  st <- spec_stats(spec)
  all <- st[nrow(st), ]
  expect_identical(all$group, "All")
  expect_equal(all$n, 4L)
  expect_equal(all$mean_x, mean(c(1, 2, 3, 5)))
  expect_equal(all$mean_y, mean(c(1, 2, 3, 2)))
  expect_equal(all$sd_x, stats::sd(c(1, 2, 3, 5)))
  expect_equal(all$r, stats::cor(c(1, 2, 3, 5), c(1, 2, 3, 2)))
  expect_null(attr(st, "overall_r"))
})

test_that("big scatter is fast", {
  n <- 50000
  x <- list(tool = "scatter", xlim = c(0, 1), ylim = c(0, 1),
            groups = c("A", "B", "C"),
            points = list(x = stats::runif(n), y = stats::runif(n),
                          group = sample(c("A", "B", "C"), n, replace = TRUE)))
  el <- system.time(df <- dcr_sample(as_dcr_spec(x)))[["elapsed"]]
  expect_lt(el, 1)
  expect_equal(nrow(df), n)
  expect_false(is.unsorted(as.integer(df$group)))
})

test_that("invalid scatter input is rejected", {
  expect_error(sc(list(x = 1:2, y = 1, group = "A")), "same length")
  expect_error(sc(list(x = 1, y = 2, group = "A"), groups = c("A", "A")), "unique")
  expect_error(as_dcr_spec(list(tool = "scatter", xlim = c(1, 1), ylim = c(0, 1),
                                groups = "A", points = list())), "xlim")
})
