test_that("dcr_scatter and dcr_scatter_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_scatter", "dcr_scatter_addin") %in% exports))
})

test_that("scatter_tool() forwards the scatter controls", {
  tool <- scatter_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "scatter")
  expect_equal(tool$controls, c("groups", "active", "mode", "brush", "density",
                                "xlim", "ylim", "names"))
})

test_that("the scatter UI has the tool, its controls and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(scatter_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="scatter"', fixed = TRUE)
  for (id in paste0("ctl_", scatter_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/scatter.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "scatter.js")))
})

test_that("scatter options reach the JS tool as JSON", {
  tool <- scatter_tool(list(xlim = c(-5, 5), groups = "A"))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$xlim, c(-5, 5))
  expect_equal(parsed$ylim, c(0, 10))
  expect_equal(parsed$groups, "A")
  expect_equal(parsed$names, list(x = "x", y = "y", group = "group"))
  expect_equal(parsed$brush, 0.08)
  expect_equal(parsed$density, 40)
  expect_equal(parsed$mode, "spray")
})

test_that("scatter control values are validated before reaching JS", {
  v <- scatter_tool()$validate
  expect_equal(v("groups", " A , B,C "), c("A", "B", "C"))
  expect_error(v("groups", "A, A"), "unique")
  expect_error(v("groups", "A, , B"), "empty")
  expect_error(v("groups", ""), "1 to 10")
  expect_equal(v("xlim", list(-5, 5)), c(-5, 5))
  expect_error(v("xlim", c(5, 5)), "xlim")
  expect_error(v("ylim", list(10, NULL)), "ylim")
  expect_equal(v("names", list(x = " h ", y = "w", group = "g")),
               list(x = "h", y = "w", group = "g"))
  expect_error(v("names", list(x = "a", y = "a", group = "g")), "unique")
  expect_equal(v("mode", "erase"), "erase")
})

test_that("an invalid control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(scatter_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_xlim = list(0, 10), ctl_groups = "A, B, C")
      session$setInputs(ctl_xlim = list(5, 1))
      session$setInputs(ctl_groups = "A,B")
    })
  expect_equal(notes, "xlim must be two finite numbers with the first less than the second.")
  expect_equal(sent, list(list(groups = c("A", "B"))))
})

test_that("dcr_scatter validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_scatter(xlim = c(-5, 5), groups = c(" a", "b"),
                           names = c("h", "w", "sp")), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$xlim, c(-5, 5))
  expect_equal(got$tool$options$groups, c("a", "b"))
  expect_equal(got$tool$options$names, list(x = "h", y = "w", group = "sp"))

  dcr_scatter(names = c(group = "g", x = "u", y = "v"))
  expect_equal(got$tool$options$names, list(x = "u", y = "v", group = "g"))

  expect_error(dcr_scatter(xlim = c(5, 5)), "xlim")
  expect_error(dcr_scatter(ylim = c(10, 0)), "ylim")
  expect_error(dcr_scatter(groups = c("A", "A")), "unique")
  expect_error(dcr_scatter(groups = LETTERS[1:11]), "1 to 10")
  expect_error(dcr_scatter(names = c("x", "y")), "names")
})

test_that("dcr_scatter_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_scatter_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Scatter addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_scatter_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Scatter")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
