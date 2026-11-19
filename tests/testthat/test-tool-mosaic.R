test_that("dcr_mosaic and dcr_mosaic_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_mosaic", "dcr_mosaic_addin") %in% exports))
})

test_that("mosaic_tool() forwards the mosaic controls in order", {
  tool <- mosaic_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "mosaic")
  expect_equal(tool$controls, c("cols", "rows", "n", "names"))
})

test_that("the mosaic UI has the tool, its controls, actions and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(mosaic_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="mosaic"', fixed = TRUE)
  for (id in paste0("ctl_", mosaic_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  for (a in c("independent", "uniform")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/mosaic.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "mosaic.js")))
})

test_that("mosaic options reach the JS tool as JSON", {
  tool <- mosaic_tool(list(cols = c("a", "b", "c"), rows = c("x", "y"),
                           n = 77, names = list(col = "g", row = "h")))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$cols, c("a", "b", "c"))
  expect_equal(parsed$rows, c("x", "y"))
  expect_equal(parsed$n, 77)
  expect_equal(parsed$names$col, "g")
  expect_equal(parsed$names$row, "h")
})

test_that("mosaic control values are validated before reaching JS", {
  v <- mosaic_tool()$validate
  expect_equal(v("cols", " A , B,C "), c("A", "B", "C"))
  expect_error(v("cols", "A"), "2 to 10")
  expect_error(v("cols", "A, A"), "unique")
  expect_error(v("rows", "A, , B"), "empty")
  expect_error(v("rows", paste(letters[1:11], collapse = ",")), "2 to 10")
  expect_equal(v("n", 200), 200)
  expect_error(v("n", 0), "n must")
  expect_error(v("n", 2.5), "n must")
  expect_error(v("n", NA), "n must")
  expect_error(v("n", 2e6), "n must")
  expect_equal(v("names", c(col = "a", row = "b")), list(col = "a", row = "b"))
  expect_error(v("names", c("a", "a")), "unique")
  expect_error(v("names", "a"), "names must")
})

test_that("an invalid mosaic control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(mosaic_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_n = 200, ctl_cols = "A, B")
      session$setInputs(ctl_n = 0)
      session$setInputs(ctl_n = 300)
    })
  expect_match(notes, "n must be", all = FALSE)
  expect_equal(sent, list(list(n = 300)))
})

test_that("dcr_mosaic validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_mosaic(cols = c(" a", "b"), rows = c("x ", "y", "z"),
                          n = 9, names = c(col = "u", row = "w")), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$cols, c("a", "b"))
  expect_equal(got$tool$options$rows, c("x", "y", "z"))
  expect_equal(got$tool$options$n, 9)
  expect_equal(got$tool$options$names, list(col = "u", row = "w"))

  dcr_mosaic()
  expect_equal(got$tool$options$cols, c("No", "Yes"))
  expect_equal(got$tool$options$rows, c("Healthy", "Sick"))
  expect_equal(got$tool$options$n, 200)
  expect_equal(got$tool$options$names, list(col = "exposure", row = "outcome"))

  # names in col, row order or reversed with names
  dcr_mosaic(names = c(row = "r", col = "c"))
  expect_equal(got$tool$options$names, list(col = "c", row = "r"))

  expect_error(dcr_mosaic(cols = "A"), "cols must have 2 to 10")
  expect_error(dcr_mosaic(rows = "A"), "rows must have 2 to 10")
  expect_error(dcr_mosaic(rows = c("A", "A")), "rows must be unique")
  expect_error(dcr_mosaic(cols = c("", "B")), "cols must not")
  expect_error(dcr_mosaic(n = 0), "n must")
  expect_error(dcr_mosaic(n = 2.5), "n must")
  expect_error(dcr_mosaic(n = c(1, 2)), "n must")
  expect_error(dcr_mosaic(n = 2e6), "n must")
  expect_error(dcr_mosaic(names = "a"), "names must")
  expect_error(dcr_mosaic(names = c("a", "a")), "unique")
})

test_that("dcr_mosaic_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_mosaic_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Mosaic addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_mosaic_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Mosaic (contingency table)")
  expect_equal(unname(row[1, "Description"]),
               "Draw an exact two-way contingency table and insert code to load it")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
