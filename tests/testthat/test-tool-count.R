test_that("dcr_count and dcr_count_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_count", "dcr_count_addin") %in% exports))
})

test_that("count_tool() forwards the count controls", {
  tool <- count_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "count")
  expect_equal(tool$controls, c("variables", "categories", "ymax"))
})

test_that("the count UI has the tool, its controls, actions and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(count_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="count"', fixed = TRUE)
  for (id in paste0("ctl_", count_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  for (a in c("align-top", "align-middle", "align-bottom")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/count.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "count.js")))
})

test_that("count options reach the JS tool as JSON", {
  tool <- count_tool(list(variables = "A", categories = c("x", "y"),
                          ymax = 7))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$variables, "A")
  expect_equal(parsed$categories, c("x", "y"))
  expect_equal(parsed$ymax, 7)
})

test_that("count control values are validated before reaching JS", {
  v <- count_tool()$validate
  expect_equal(v("variables", " A , B,C "), c("A", "B", "C"))
  expect_error(v("variables", "A, A"), "unique")
  expect_error(v("variables", "A, , B"), "empty")
  expect_equal(v("categories", "x, y"), c("x", "y"))
  expect_error(v("categories", "x, x"), "categories must be unique")
  expect_error(v("categories", paste(letters[1:11], collapse = ",")), "1 to 10")
  expect_equal(v("ymax", 20), 20)
  expect_error(v("ymax", 0), "ymax must")
  expect_error(v("ymax", 2.5), "ymax must")
  expect_error(v("ymax", NA), "ymax must")
  expect_error(v("ymax", 2e6), "ymax must")
})

test_that("an invalid count control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(count_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_ymax = 20, ctl_variables = "A")
      session$setInputs(ctl_ymax = 0)
      session$setInputs(ctl_ymax = 30)
    })
  expect_match(notes, "ymax must be", all = FALSE)
  expect_equal(sent, list(list(ymax = 30)))
})

test_that("dcr_count validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_count(variables = c(" a", "b"), categories = c("x ", "y"),
                         ymax = 9), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$variables, c("a", "b"))
  expect_equal(got$tool$options$categories, c("x", "y"))
  expect_equal(got$tool$options$ymax, 9)

  dcr_count()
  expect_equal(got$tool$options$variables, c("V1", "V2"))
  expect_equal(got$tool$options$categories, c("C1", "C2", "C3"))
  expect_equal(got$tool$options$ymax, 20)

  expect_error(dcr_count(variables = c("A", "A")), "variables must be unique")
  expect_error(dcr_count(categories = c("", "B")), "categories must not")
  expect_error(dcr_count(categories = "x, y", variables = character()),
               "variables must have")
  expect_error(dcr_count(ymax = 0), "ymax must")
  expect_error(dcr_count(ymax = 1.5), "ymax must")
  expect_error(dcr_count(ymax = c(1, 2)), "ymax must")
})

test_that("dcr_count_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_count_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Count addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_count_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Count")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
