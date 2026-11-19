mosaic_json <- function(...) {
  base <- list(tool = "mosaic", cols = c("a", "b", "c"), rows = c("x", "y"),
               names = list(col = "exposure", row = "outcome"),
               counts = list(c(3, 0, 5), c(2, 0, 7)))
  over <- list(...)
  base[names(over)] <- over
  base
}

test_that("a 3 x 2 table with zeros round-trips through sampling", {
  spec <- as_dcr_spec(mosaic_json())
  expect_s3_class(spec, "dcr_spec_mosaic")
  expect_identical(typeof(spec$counts), "integer")
  expect_equal(dimnames(spec$counts), list(c("x", "y"), c("a", "b", "c")))
  df <- sample_spec(spec, 1)
  expect_equal(nrow(df), 17L)
  expect_equal(names(df), c("exposure", "outcome"))
  expect_equal(levels(df[[1]]), c("a", "b", "c"))
  expect_equal(levels(df[[2]]), c("x", "y"))
  tab <- table(df[[2]], df[[1]])
  expect_equal(unclass(tab), spec$counts, ignore_attr = "names")
  expect_equal(as.vector(tab), as.vector(spec$counts))
  # ordered by column category then row category
  expect_equal(as.character(df[[1]][1:5]), rep("a", 5))
  expect_equal(as.character(df[[2]][1:5]), c("x", "x", "x", "y", "y"))
  expect_equal(spec_n(spec), 17L)
  expect_false(spec_is_empty(spec))
  expect_equal(spec_kind(spec), "literal")
})

test_that("custom names are used for the data frame columns", {
  spec <- as_dcr_spec(mosaic_json(names = list(col = "smoker", row = "status")))
  expect_equal(names(sample_spec(spec, 1)), c("smoker", "status"))
})

test_that("stats are long form with margins", {
  spec <- as_dcr_spec(mosaic_json())
  s <- spec_stats(spec)
  expect_equal(names(s), c("col", "row", "count", "prop", "prop_in_col"))
  expect_equal(nrow(s), 4L * 3L)
  expect_equal(s$col[1:3], rep("a", 3))
  expect_equal(s$row[1:3], c("x", "y", "Total"))
  expect_equal(s$count[s$col == "a" & s$row == "Total"], 5)
  expect_equal(s$count[s$col == "c" & s$row == "Total"], 12)
  expect_equal(s$count[s$col == "Total" & s$row == "x"], 8)
  expect_equal(s$count[s$col == "Total" & s$row == "y"], 9)
  expect_equal(s$count[s$col == "Total" & s$row == "Total"], 17)
  expect_equal(s$prop[s$col == "a" & s$row == "x"], 3 / 17)
  expect_equal(s$prop_in_col[s$col == "a" & s$row == "x"], 3 / 5)
  expect_true(all(is.na(s$prop_in_col[s$col == "b"])))
  expect_equal(s$prop_in_col[s$col == "Total" & s$row == "x"], 8 / 17)
})

test_that("counts can come as a list of rows or a matrix", {
  m <- matrix(c(3, 2, 0, 0, 5, 7), nrow = 2)
  a <- as_dcr_spec(mosaic_json())
  b <- as_dcr_spec(mosaic_json(counts = m))
  expect_equal(a$counts, b$counts)
  json <- jsonlite::toJSON(mosaic_json(), auto_unbox = TRUE)
  c <- as_dcr_spec(jsonlite::fromJSON(json, simplifyVector = TRUE))
  expect_equal(a$counts, c$counts)
})

test_that("invalid mosaic specs are rejected", {
  bad <- function(...) as_dcr_spec(mosaic_json(...))
  expect_error(bad(counts = list(c(1.5, 0, 5), c(2, 0, 7))), "whole numbers")
  expect_error(bad(counts = list(c(-1, 0, 5), c(2, 0, 7))), "whole numbers")
  expect_error(bad(counts = matrix(c(NA, 2, 0, 0, 5, 7), nrow = 2)),
               "whole numbers")
  expect_error(bad(counts = matrix(c(Inf, 2, 0, 0, 5, 7), nrow = 2)),
               "whole numbers")
  expect_error(bad(counts = list(c(1, 2), c(3, 4))), "rows x cols")
  expect_error(bad(counts = list(c(1, 2, 3))), "rows x cols")
  # ragged rows are never recycled
  expect_error(bad(counts = list(c(1, 2, 3), c(1, 2))), "rows x cols")
  expect_error(bad(counts = list(c(1, 2, 3), c(1, 2, 3, 4, 5, 6))), "rows x cols")
  expect_error(bad(counts = list(c(0, 0, 0), c(0, 0, 0))), "at least 1")
  expect_error(bad(counts = list(c(1e6, 1, 0), c(0, 0, 0))), "at most 1e6")
  expect_silent(bad(counts = list(c(1e6, 0, 0), c(0, 0, 0))))
  expect_error(bad(cols = c("a", "a", "b")), "unique")
  expect_error(bad(rows = letters[1:11]), "2 to 10")
  expect_error(bad(rows = "x"), "2 to 10")
  expect_error(bad(names = list(col = "same", row = "same")), "unique")
  expect_error(bad(names = list(col = "only")), "col and row")
})

test_that("mosaic_names accepts positional and named vectors", {
  expect_equal(mosaic_names(c("a", "b")), list(col = "a", row = "b"))
  expect_equal(mosaic_names(c(row = "r", col = "c")), list(col = "c", row = "r"))
  expect_error(mosaic_names(c("a", "b", "c")), "col and row")
  expect_error(mosaic_names(c("a", " ")), "empty")
})
test_that("mosaic_names rejects malformed and unknown names", {
  expect_error(mosaic_names(list(col = c("a", "b"), row = "c")), "names must")
  expect_error(mosaic_names(list("a", c("b", "c"))), "names must")
  expect_error(mosaic_names(c(col = "a", other = "b")), "names must")
  expect_error(mosaic_names(c(a = "x", b = "y")), "names must")
  expect_equal(mosaic_names(c(row = "r", col = "c")), list(col = "c", row = "r"))
})
