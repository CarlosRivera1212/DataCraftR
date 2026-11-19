local_store <- function(env = parent.frame()) {
  withr::local_envvar(R_USER_DATA_DIR = withr::local_tempdir(.local_envir = env),
                      .local_envir = env)
}

sc_spec <- function() {
  as_dcr_spec(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                   groups = c("A", "B"),
                   points = list(x = c(1, 2, 3), y = c(4, 5, 6),
                                 group = c("A", "B", "A"))))
}

bx_spec <- function(...) {
  as_dcr_spec(list(tool = "boxplot", family = "normal", variables = "V1",
                   q1 = 2, q2 = 3, q3 = 5, ylim = c(0, 10), n = 50, ...))
}

test_that("save then load gives the same literal data", {
  local_store()
  spec <- sc_spec()
  id <- dcr_save(spec)
  expect_match(id, "^scatter_[0-9]{8}_[0-9]{6}$")
  expect_true(file.exists(file.path(dcr_store_dir(), paste0(id, ".rds"))))
  expect_equal(dcr_load(id), dcr_sample(spec))
})

test_that("population specs reload reproducibly and seed overrides", {
  local_store()
  spec <- bx_spec(seed = 11)   # one spec: `created` must not differ
  id <- dcr_save(spec)
  a <- dcr_load(id)
  b <- dcr_load(id)
  expect_equal(a, b)
  expect_equal(a, dcr_sample(spec))
  expect_false(isTRUE(all.equal(dcr_load(id, seed = 7)$V1, a$V1)))
  expect_equal(dcr_load(id, seed = 7)$V1, dcr_load(id, seed = 7)$V1)
  expect_equal(nrow(dcr_load(id, n = 10)), 10L)
})

test_that("same-second saves get a numeric suffix", {
  local_store()
  tm <- as.POSIXct("2026-11-17 15:30:12")
  spec <- new_dcr_spec("x", n = 1)
  expect_equal(dcr_save(spec, time = tm), "x_20261117_153012")
  expect_equal(dcr_save(spec, time = tm), "x_20261117_153012_2")
  expect_equal(dcr_save(spec, time = tm), "x_20261117_153012_3")
})

test_that("dcr_list is empty then newest first", {
  local_store()
  empty <- dcr_list()
  expect_equal(nrow(empty), 0L)
  expect_equal(names(empty), c("id", "tool", "created", "n"))
  s1 <- as_dcr_spec(list(tool = "scatter", xlim = c(0, 1), ylim = c(0, 1),
                         groups = "A", points = list()))
  s1$created <- "2026-01-01T10:00:00Z"
  s2 <- bx_spec()
  s2$created <- "2026-02-01T10:00:00Z"
  i1 <- dcr_save(s1, time = as.POSIXct("2026-01-01 10:00:00"))
  i2 <- dcr_save(s2, time = as.POSIXct("2026-02-01 10:00:00"))
  writeLines("junk", file.path(dcr_store_dir(), "junk.rds"))
  res <- dcr_list()
  expect_equal(nrow(res), 2L)
  expect_equal(res$id, c(i2, i1))
  expect_equal(res$tool, c("boxplot", "scatter"))
  expect_equal(res$created, c("2026-02-01T10:00:00Z", "2026-01-01T10:00:00Z"))
})

test_that("delete removes the file and load then errors", {
  local_store()
  id <- dcr_save(sc_spec())
  expect_true(dcr_delete(id))
  expect_false(file.exists(file.path(dcr_store_dir(), paste0(id, ".rds"))))
  expect_error(dcr_load(id), "dcr_list")
  expect_error(dcr_delete(id), "dcr_list")
})

test_that("invalid ids are rejected before touching the file system", {
  local_store()
  expect_error(dcr_load("../evil"), "dcr_list")
  expect_error(dcr_delete("a/b"), "dcr_list")
  expect_error(dcr_load(c("a", "b")), "dcr_list")
  expect_error(dcr_load(NA_character_), "dcr_list")
})

test_that("unwritable store gives a clear error", {
  blocker <- withr::local_tempfile()
  writeLines("x", blocker)
  withr::local_envvar(R_USER_DATA_DIR = blocker)
  expect_error(dcr_save(sc_spec()), "Could not save to")
})

test_that("dcr_load leaves the global RNG state untouched", {
  local_store()
  id <- dcr_save(bx_spec(seed = 11))
  old <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  withr::defer({
    if (is.null(old)) {
      if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
        rm(".Random.seed", envir = globalenv())
      }
    } else {
      assign(".Random.seed", old, envir = globalenv())
    }
  })
  set.seed(5)
  before <- get(".Random.seed", envir = globalenv())
  dcr_load(id)
  dcr_load(id, seed = 3)
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  rm(".Random.seed", envir = globalenv())
  dcr_load(id)
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})
