test_that("dcr_histogram and dcr_histogram_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_histogram", "dcr_histogram_addin") %in% exports))
})

test_that("histogram_tool() forwards the histogram controls", {
  tool <- histogram_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "histogram")
  expect_equal(tool$controls, c("variables", "active", "n", "xlim", "nbins"))
})

test_that("the histogram UI has the tool, its controls, actions and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(histogram_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="histogram"', fixed = TRUE)
  for (id in paste0("ctl_", histogram_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  for (a in c("flat", "reset")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/histogram.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "histogram.js")))
})

test_that("histogram options reach the JS tool as JSON", {
  tool <- histogram_tool(list(variables = "A", n = 50, xlim = c(-5, 5),
                              nbins = 20))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$variables, "A")
  expect_equal(parsed$n, 50)
  expect_equal(parsed$xlim, c(-5, 5))
  expect_equal(parsed$nbins, 20)
})

test_that("histogram control values are validated before reaching JS", {
  v <- histogram_tool()$validate
  expect_equal(v("variables", " A , B,C "), c("A", "B", "C"))
  expect_error(v("variables", "A, A"), "unique")
  expect_error(v("variables", "A, , B"), "empty")
  expect_equal(v("xlim", list(-5, 5)), c(-5, 5))
  expect_error(v("xlim", c(5, 5)), "xlim")
  expect_equal(v("n", 100), 100)
  expect_error(v("n", 0), "n must")
  expect_error(v("n", 2e6), "n must")
  expect_error(v("n", 10.5), "n must")
  expect_equal(v("nbins", 1), 1)
  expect_equal(v("nbins", 100), 100)
  expect_error(v("nbins", 0), "nbins must")
  expect_error(v("nbins", 101), "nbins must")
  expect_error(v("nbins", 2.5), "nbins must")
  expect_error(v("nbins", NA), "nbins must")
})

test_that("an invalid histogram control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(histogram_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_nbins = 10, ctl_variables = "A")
      session$setInputs(ctl_nbins = 0)
      session$setInputs(ctl_nbins = 20)
    })
  expect_match(notes, "nbins must be", all = FALSE)
  expect_equal(sent, list(list(nbins = 20)))
})

test_that("dcr_histogram validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_histogram(variables = c(" a", "b"), n = 50,
                             xlim = c(-5, 5), nbins = 20), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$variables, c("a", "b"))
  expect_equal(got$tool$options$n, 50)
  expect_equal(got$tool$options$xlim, c(-5, 5))
  expect_equal(got$tool$options$nbins, 20)

  dcr_histogram()
  expect_equal(got$tool$options$variables, "V1")
  expect_equal(got$tool$options$nbins, 10)

  expect_error(dcr_histogram(variables = c("A", "A")), "unique")
  expect_error(dcr_histogram(xlim = c(5, 5)), "xlim")
  expect_error(dcr_histogram(xlim = c(10, 0)), "xlim")
  expect_error(dcr_histogram(n = 0), "n must")
  expect_error(dcr_histogram(n = 1e7), "n must")
  expect_error(dcr_histogram(nbins = 0), "nbins must")
  expect_error(dcr_histogram(nbins = 101), "nbins must")
  expect_error(dcr_histogram(nbins = 7.5), "nbins must")
})

test_that("dcr_histogram_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_histogram_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Histogram addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_histogram_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Histogram")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
