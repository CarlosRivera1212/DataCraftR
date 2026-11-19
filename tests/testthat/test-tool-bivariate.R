test_that("dcr_bivariate and dcr_bivariate_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_bivariate", "dcr_bivariate_addin") %in% exports))
})

test_that("bivariate_tool() forwards the bivariate controls", {
  tool <- bivariate_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "bivariate")
  expect_equal(tool$controls, c("groups", "active", "mode", "autofit", "n",
                                "xlim", "ylim", "names"))
})

test_that("the bivariate UI has the tool, its controls, action and script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(bivariate_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="bivariate"', fixed = TRUE)
  for (id in paste0("ctl_", bivariate_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_match(html, 'data-dcr-action="reset-axes"', fixed = TRUE)
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/bivariate.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "bivariate.js")))
})

test_that("bivariate options reach the JS tool as JSON", {
  tool <- bivariate_tool(list(xlim = c(-5, 5), groups = "A", n = 50))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$xlim, c(-5, 5))
  expect_equal(parsed$ylim, c(0, 10))
  expect_equal(parsed$groups, "A")
  expect_equal(parsed$n, 50)
  expect_equal(parsed$names, list(x = "x", y = "y", group = "group"))
  expect_equal(parsed$mode, "handles")
  expect_true(parsed$autofit)
})

test_that("bivariate control values are validated before reaching JS", {
  v <- bivariate_tool()$validate
  expect_equal(v("groups", " A , B,C "), c("A", "B", "C"))
  expect_error(v("groups", "A, A"), "unique")
  expect_equal(v("xlim", list(-5, 5)), c(-5, 5))
  expect_error(v("ylim", c(5, 5)), "ylim")
  expect_equal(v("n", 20), 20)
  expect_error(v("n", 0), "whole number")
  expect_equal(v("names", list(x = " h ", y = "w", group = "g")),
               list(x = "h", y = "w", group = "g"))
  expect_equal(v("mode", "gestures"), "gestures")
})

test_that("an invalid ctl_ylim is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(bivariate_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_ylim = list(0, 10))
      session$setInputs(ctl_ylim = list(5, 1))
      session$setInputs(ctl_ylim = list(-1, 12))
    })
  expect_equal(notes, "ylim must be two finite numbers with the first less than the second.")
  expect_equal(sent, list(list(ylim = c(-1, 12))))
})

test_that("dcr_bivariate validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_bivariate(groups = c(" a", "b", "c"), n = 300,
                             xlim = c(-5, 5), names = c("h", "w", "sp")), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$groups, c("a", "b", "c"))
  expect_equal(got$tool$options$n, 300)
  expect_equal(got$tool$options$xlim, c(-5, 5))
  expect_equal(got$tool$options$names, list(x = "h", y = "w", group = "sp"))
  dcr_bivariate(n = 5e5)   # 2 groups x 5e5 = 1e6: allowed
  expect_equal(got$tool$options$n, 5e5)

  expect_error(dcr_bivariate(xlim = c(5, 5)), "xlim")
  expect_error(dcr_bivariate(ylim = c(10, 0)), "ylim")
  expect_error(dcr_bivariate(n = 0), "whole number")
  expect_error(dcr_bivariate(n = 2.5), "whole number")
  expect_error(dcr_bivariate(groups = c("A", "A")), "unique")
  expect_error(dcr_bivariate(groups = c("A", "B", "C"), n = 4e5), "at most 1e6")
  expect_error(dcr_bivariate(names = c("x", "y")), "names")
})

test_that("dcr_bivariate_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_bivariate_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Bivariate addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_bivariate_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Bivariate normal")
  expect_equal(unname(row[1, "Description"]),
               "Draw bivariate normal populations and insert code to sample them")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
