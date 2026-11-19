test_that("dcr_boxplot and dcr_boxplot_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_boxplot", "dcr_boxplot_addin") %in% exports))
})

test_that("boxplot_tool() forwards the boxplot controls", {
  tool <- boxplot_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "boxplot")
  expect_equal(tool$controls, c("variables", "active", "n", "family", "ylim"))
})

test_that("the boxplot UI has the tool, its controls, actions and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(boxplot_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="boxplot"', fixed = TRUE)
  for (id in paste0("ctl_", boxplot_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  for (a in c("align", "reset")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/boxplot.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "boxplot.js")))
})

test_that("boxplot options reach the JS tool as JSON", {
  tool <- boxplot_tool(list(variables = "A", n = 50, ylim = c(-5, 5)))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$variables, "A")
  expect_equal(parsed$n, 50)
  expect_equal(parsed$ylim, c(-5, 5))
  expect_equal(parsed$family, "normal")
})

test_that("boxplot control values are validated before reaching JS", {
  v <- boxplot_tool()$validate
  expect_equal(v("variables", " A , B,C "), c("A", "B", "C"))
  expect_error(v("variables", "A, A"), "unique")
  expect_error(v("variables", "A, , B"), "empty")
  expect_error(v("variables", ""), "1 to 10")
  expect_equal(v("ylim", list(-5, 5)), c(-5, 5))
  expect_error(v("ylim", c(5, 5)), "ylim")
  expect_equal(v("n", 100), 100)
  expect_error(v("n", 0), "n must")
  expect_error(v("n", 2e6), "n must")
  expect_error(v("n", 10.5), "n must")
  expect_error(v("n", NA), "n must")
  expect_error(v("n", NULL), "n must")
  expect_equal(v("family", "uniform"), "uniform")
  expect_error(v("family", "cauchy"), "family")
})

test_that("an invalid boxplot control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(boxplot_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_n = 100, ctl_variables = "A, B, C")
      session$setInputs(ctl_n = 0)
      session$setInputs(ctl_n = 500)
    })
  expect_match(notes, "n must be", all = FALSE)
  expect_equal(sent, list(list(n = 500)))
})

test_that("dcr_boxplot validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_boxplot(variables = c(" a", "b"), n = 50,
                           family = "uniform", ylim = c(-5, 5)), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$variables, c("a", "b"))
  expect_equal(got$tool$options$n, 50)
  expect_equal(got$tool$options$family, "uniform")
  expect_equal(got$tool$options$ylim, c(-5, 5))

  dcr_boxplot()
  expect_equal(got$tool$options$family, "normal")
  expect_equal(got$tool$options$variables, c("V1", "V2", "V3"))

  expect_error(dcr_boxplot(variables = c("A", "A")), "unique")
  expect_error(dcr_boxplot(variables = LETTERS[1:11]), "1 to 10")
  expect_error(dcr_boxplot(ylim = c(5, 5)), "ylim")
  expect_error(dcr_boxplot(n = 0), "n must")
  expect_error(dcr_boxplot(n = 1e7), "n must")
  expect_error(dcr_boxplot(family = "cauchy"), "should be one of")
})

test_that("dcr_boxplot_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_boxplot_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Boxplot addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_boxplot_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Boxplot")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
