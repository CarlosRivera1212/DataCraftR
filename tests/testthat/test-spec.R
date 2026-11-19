test_that("new_dcr_spec sets class and common fields", {
  s <- new_dcr_spec("demo", a = 1, n = 10L, seed = 3L)
  expect_s3_class(s, c("dcr_spec_demo", "dcr_spec"))
  expect_equal(s$version, 1L); expect_equal(s$n, 10L); expect_match(s$created, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T")
})
test_that("unknown tool errors", expect_error(as_dcr_spec(list(tool = "nope")), "Unknown DataCraftR tool: nope"))
test_that("check_names trims and rejects bad names", {
  expect_equal(check_names(c(" a", "my var"), "groups"), c("a", "my var"))
  expect_error(check_names(c("a", "a"), "groups"), "unique")
  expect_error(check_names(c("a", "  "), "groups"), "empty")
  expect_error(check_names(paste0("g", 1:11), "groups"), "1 to 10")
})
test_that("check_range rejects reversed and zero-width", {
  expect_error(check_range(c(5, 5), "xlim"), "xlim"); expect_error(check_range(c(10, 0), "xlim"), "xlim")
  expect_error(check_range(c(0, Inf), "xlim"), "xlim"); expect_equal(check_range(c(-1, 1), "xlim"), c(-1, 1))
})
test_that("dcr_spec extracts or errors", {
  df <- structure(data.frame(x = 1), dcr_spec = new_dcr_spec("demo"))
  expect_s3_class(dcr_spec(df), "dcr_spec"); expect_error(dcr_spec(data.frame()), "not created by DataCraftR")
})

handler_roundtrip <- function(x) {
  got <- dcr_spec_input_handler(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA),
                                NULL, "tool")
  want <- as_dcr_spec(x)
  got$created <- want$created <- NULL
  expect_equal(got, want)
}

test_that("the dcr.spec input handler round-trips JSON from JS", {
  expect_null(dcr_spec_input_handler(NULL, NULL, "tool"))
  handler_roundtrip(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                         groups = c("A", "B"),
                         points = list(x = c(1, 2.5), y = c(3, 4),
                                       group = c("B", "A"))))
  handler_roundtrip(list(tool = "scatter", xlim = c(0, 10), ylim = c(-1, 1),
                         groups = c("A", "B"),
                         points = list(x = numeric(0), y = numeric(0),
                                       group = character(0))))
  handler_roundtrip(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                         groups = "A",
                         points = list(x = 1, y = 2, group = "A")))
})

test_that("an invalid spec becomes a dcr_spec_error instead of an error", {
  bad <- jsonlite::toJSON(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                               groups = c("A", "A"),
                               points = list(x = 1, y = 2, group = "A")),
                          auto_unbox = TRUE)
  e <- dcr_spec_input_handler(bad, NULL, "tool")
  expect_s3_class(e, "dcr_spec_error")
  expect_match(e$message, "groups must be unique")
  expect_s3_class(dcr_spec_input_handler('{"tool": "nope"}', NULL, "tool"),
                  "dcr_spec_error")
})
