test_that("insert_target puts code on the line after the cursor", {
  expect_identical(insert_target(c("a", "b"), 1, "x.R"),
                   list(row = 2, wrap = FALSE))
})

test_that("insert_target wraps only in Rmd/qmd prose", {
  txt <- c("intro", "", "```{r}", "x <- 1", "```", "more prose")
  expect_true(insert_target(txt, 2, "a.qmd")$wrap)
  expect_true(insert_target(txt, 6, "A.RMD")$wrap)
  expect_false(insert_target(txt, 4, "a.qmd")$wrap)
  expect_true(insert_target(txt, 5, "a.Rmd")$wrap)  # on the closing fence
  expect_false(insert_target(txt, 3, "a.Rmd")$wrap)  # on the opening fence
  expect_false(insert_target(txt, 2, "")$wrap)
  expect_false(insert_target(txt, 2, "a.R")$wrap)
})

test_that("dcr_insert_code prints outside RStudio", {
  local_mocked_bindings(isAvailable = function(...) FALSE, .package = "rstudioapi")
  expect_output(dcr_insert_code(c("a", "b")), "a\nb")
})

lines3 <- c("l1", "l2", "l3")
ctx <- function(path, contents, row, id = "doc1") {
  list(id = id, path = path, contents = contents,
       selection = list(list(range = list(start = c(row = row, column = 1),
                                          end = c(row = row, column = 1)))))
}

test_that("R script: inserts at cursor row + 1", {
  calls <- list()
  local_mocked_bindings(
    isAvailable = function(...) TRUE,
    getSourceEditorContext = function() ctx("x.R", c("a", "b", "c"), 1),
    insertText = function(location, text, id) {
      calls[[length(calls) + 1]] <<- list(location = location, text = text, id = id)
    },
    .package = "rstudioapi")
  dcr_insert_code(lines3)
  expect_length(calls, 1)
  expect_equal(unname(unclass(calls[[1]]$location)), c(2, 1))
  expect_identical(calls[[1]]$text, "l1\nl2\nl3\n")
  expect_identical(calls[[1]]$id, "doc1")
})

test_that("qmd prose: wraps in an r chunk", {
  calls <- list()
  local_mocked_bindings(
    isAvailable = function(...) TRUE,
    getSourceEditorContext = function() ctx("x.qmd", c("prose", "more"), 1),
    insertText = function(location, text, id) {
      calls[[length(calls) + 1]] <<- list(location = location, text = text)
    },
    .package = "rstudioapi")
  dcr_insert_code(lines3)
  expect_identical(calls[[1]]$text, "```{r}\nl1\nl2\nl3\n```\n")
})

test_that("cursor past the last line prefixes a newline", {
  calls <- list()
  local_mocked_bindings(
    isAvailable = function(...) TRUE,
    getSourceEditorContext = function() ctx("x.R", c("a", "b"), 2),
    insertText = function(location, text, id) {
      calls[[length(calls) + 1]] <<- list(location = location, text = text)
    },
    .package = "rstudioapi")
  dcr_insert_code(lines3)
  expect_identical(calls[[1]]$text, "\nl1\nl2\nl3\n")
})

test_that("no document sends to the console", {
  for (cx in list(NULL, list(id = ""))) {
    sent <- NULL
    local_mocked_bindings(
      isAvailable = function(...) TRUE,
      getSourceEditorContext = function() cx,
      sendToConsole = function(code, execute = TRUE, ...) {
        sent <<- list(code = code, execute = execute)
      },
      .package = "rstudioapi")
    dcr_insert_code(lines3)
    expect_identical(sent, list(code = "l1\nl2\nl3", execute = TRUE))
  }
})

test_that("insert_target is not fooled by plain or other-language fences", {
  # a plain ``` block above: its closing fence is not the end of an r chunk
  txt <- c("prose", "```", "plain code", "```", "", "```{r}", "x <- 1",
           "```", "after")
  expect_true(insert_target(txt, 1, "a.Rmd")$wrap)
  expect_true(insert_target(txt, 3, "a.Rmd")$wrap)   # inside a plain block
  expect_true(insert_target(txt, 5, "a.Rmd")$wrap)
  expect_false(insert_target(txt, 7, "a.Rmd")$wrap)  # inside the r chunk
  expect_true(insert_target(txt, 9, "a.Rmd")$wrap)
  # a ```bash block: its closing fence used to count as closing a chunk
  txt <- c("```{r}", "x <- 1", "```", "```bash", "ls", "```", "```{r}",
           "y <- 2", "```", "end")
  expect_true(insert_target(txt, 5, "a.qmd")$wrap)
  expect_true(insert_target(txt, 6, "a.qmd")$wrap)
  expect_false(insert_target(txt, 8, "a.qmd")$wrap)
  expect_true(insert_target(txt, 10, "a.qmd")$wrap)
  # an r chunk opened after a bash block is still detected
  txt <- c("```bash", "ls", "```", "```{r}", "z <- 3")
  expect_false(insert_target(txt, 5, "a.qmd")$wrap)
})
