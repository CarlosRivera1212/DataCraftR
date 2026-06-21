test_that("save_data_dcr saves and retrieves data for box type", {
  data <- data.frame(x = 1:5, y = 6:10)
  tmp <- save_data_dcr(data, type = "box")
  expect_true(file.exists(tmp))
  restored <- readRDS(tmp)
  expect_equal(restored, data)
  unlink(tmp)
})

test_that("save_data_dcr saves and retrieves data for scatter type", {
  data <- data.frame(x = runif(10), y = runif(10), g = rep(c("A", "B"), each = 5))
  tmp <- save_data_dcr(data, type = "scatter")
  expect_true(file.exists(tmp))
  restored <- readRDS(tmp)
  expect_equal(restored, data)
  unlink(tmp)
})

test_that("save_data_dcr saves and retrieves data for hist type", {
  data <- list(rnorm(100))
  tmp <- save_data_dcr(data, type = "hist", par = c(10, -3, 3, 30))
  expect_true(file.exists(tmp))
  restored <- readRDS(tmp)
  expect_equal(restored, data)
  unlink(tmp)
})

test_that("save_data_dcr saves and retrieves data for count type", {
  data <- data.frame(cat = rep(c("A", "B", "C"), each = 10), var = sample(letters[1:3], 30, replace = TRUE))
  tmp <- save_data_dcr(data, type = "count")
  expect_true(file.exists(tmp))
  restored <- readRDS(tmp)
  expect_equal(restored, data)
  unlink(tmp)
})

test_that("save_data_dcr uses tempfile and file paths are unique", {
  data <- data.frame(x = 1:3)
  tmp1 <- save_data_dcr(data, type = "box")
  tmp2 <- save_data_dcr(data, type = "box")
  expect_true(file.exists(tmp1))
  expect_true(file.exists(tmp2))
  expect_false(tmp1 == tmp2)
  unlink(tmp1)
  unlink(tmp2)
})
