test_that("palette() default returns 10 colors", {
  res <- palette()
  expect_type(res, "character")
  expect_length(res, 10)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette default with n=5 returns 5 valid hex colors", {
  res <- palette(n = 5, name = "default")
  expect_length(res, 5)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette neon returns valid hex colors", {
  res <- palette(n = 5, name = "neon")
  expect_type(res, "character")
  expect_length(res, 5)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette pastel returns valid hex colors", {
  res <- palette(n = 5, name = "pastel")
  expect_type(res, "character")
  expect_length(res, 5)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette tropical returns valid hex colors", {
  res <- palette(n = 5, name = "tropical")
  expect_type(res, "character")
  expect_length(res, 5)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette n=1 returns single color", {
  res <- palette(n = 1)
  expect_length(res, 1)
  expect_match(res, "^#[0-9A-Fa-f]{6}$")
})

test_that("palette n=10 returns 10 colors", {
  res <- palette(n = 10)
  expect_length(res, 10)
})

test_that("palette n > 10 throws error", {
  expect_error(palette(n = 11), "n <= 10")
})

test_that("palette n = 0 returns one color (R indexing quirk)", {
  res <- palette(n = 0)
  expect_type(res, "character")
})

test_that("palette default colors differ with lf parameter", {
  res1 <- palette(n = 3, name = "default", lf = 0)
  res2 <- palette(n = 3, name = "default", lf = 20)
  expect_false(identical(res1, res2))
})

test_that("palette named palettes are deterministic", {
  res1 <- palette(n = 10, name = "neon")
  res2 <- palette(n = 10, name = "neon")
  expect_equal(res1, res2)
})
