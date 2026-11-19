registerS3method("sample_spec", "dcr_spec_demo",
                 function(spec, n) data.frame(v = stats::runif(n)),
                 envir = asNamespace("DataCraftR"))
registerS3method("spec_kind", "dcr_spec_demo",
                 function(spec) "population",
                 envir = asNamespace("DataCraftR"))
registerS3method("sample_spec", "dcr_spec_litdemo",
                 function(spec, n) structure(data.frame(v = 1:3), dropped = 2L),
                 envir = asNamespace("DataCraftR"))
registerS3method("spec_kind", "dcr_spec_litdemo",
                 function(spec) "literal",
                 envir = asNamespace("DataCraftR"))

demo_spec <- function(n = 10L, seed = NULL) {
  DataCraftR:::new_dcr_spec("demo", n = n, seed = seed)
}

test_that("same seed gives identical data, different seed differs", {
  a <- dcr_sample(demo_spec(), seed = 42)
  b <- dcr_sample(demo_spec(), seed = 42)
  d <- dcr_sample(demo_spec(), seed = 43)
  expect_identical(as.data.frame(a)$v, as.data.frame(b)$v)
  expect_false(identical(a$v, d$v))
})

test_that("n argument overrides spec$n", {
  res <- dcr_sample(demo_spec(10L), n = 5, seed = 42)
  expect_equal(nrow(res), 5L)
  expect_equal(dcr_spec(res)$n, 5L)
  expect_equal(nrow(dcr_sample(demo_spec(7L))), 7L)
})

test_that("spec attribute records seed and n used", {
  res <- dcr_sample(demo_spec(), n = 5, seed = 42)
  expect_equal(attr(res, "dcr_spec")$seed, 42)
  expect_equal(attr(res, "dcr_spec")$n, 5)
})

test_that("invalid n errors", {
  expect_error(dcr_sample(demo_spec(), n = 0), "n must be")
  expect_error(dcr_sample(demo_spec(), n = 2.5), "n must be")
  expect_error(dcr_sample(demo_spec(), n = c(1, 2)), "n must be")
  expect_error(dcr_sample(demo_spec(), n = NA), "n must be")
})

test_that("literal tools ignore n and seed and keep other attributes", {
  spec <- DataCraftR:::new_dcr_spec("litdemo")
  res <- dcr_sample(spec, n = 99, seed = 1)
  expect_equal(nrow(res), 3L)
  expect_null(attr(res, "dcr_spec")$n)
  expect_null(attr(res, "dcr_spec")$seed)
  expect_equal(attr(res, "dropped"), 2L)
})

test_that("a generated seed is recorded and reproduces the data", {
  res <- dcr_sample(demo_spec())
  s <- dcr_spec(res)$seed
  expect_true(is.numeric(s) && length(s) == 1L && s == round(s) && s %in% 1:1e6)
  expect_identical(dcr_sample(dcr_spec(res))$v, res$v)
})

# Restore the global RNG state after the test, whatever it does to it.
local_global_rng <- function(env = parent.frame()) {
  old <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  withr::defer({
    if (is.null(old)) {
      if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
        rm(".Random.seed", envir = globalenv())
      }
    } else {
      assign(".Random.seed", old, envir = globalenv())
    }
  }, envir = env)
}

test_that("dcr_sample leaves the global RNG state untouched", {
  local_global_rng()
  set.seed(123)
  before <- get(".Random.seed", envir = globalenv())
  dcr_sample(demo_spec(), seed = 42)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  dcr_sample(demo_spec())                      # seed drawn internally
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  expect_identical(stats::runif(1), {set.seed(123); stats::runif(1)})
})

test_that("dcr_sample does not create a global RNG state", {
  local_global_rng()
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
    rm(".Random.seed", envir = globalenv())
  }
  dcr_sample(demo_spec(), seed = 42)
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
  dcr_sample(demo_spec())
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})
