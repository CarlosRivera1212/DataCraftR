test_that("dcr_density and dcr_density_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_density", "dcr_density_addin") %in% exports))
})

test_that("density_tool() forwards the density controls", {
  tool <- density_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "density")
  expect_equal(tool$controls,
               c("variables", "active", "mode", "brush", "n", "xlim"))
})

test_that("the density UI has the tool, its controls, actions and its script", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(density_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="density"', fixed = TRUE)
  for (id in paste0("ctl_", density_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  for (a in c("bell", "flat", "skew")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  dcr <- Filter(function(d) d$name == "dcr", rendered$dependencies)[[1]]
  expect_true("tools/density.js" %in% dcr$script)
  expect_true(file.exists(file.path(dcr$src$file, "tools", "density.js")))
})

test_that("density options reach the JS tool as JSON", {
  tool <- density_tool(list(variables = "A", n = 50, xlim = c(-5, 5)))
  html <- htmltools::renderTags(dcr_gadget_ui(tool))$html
  opts <- regmatches(html, regexpr('data-options="[^"]*"', html))
  opts <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", opts),
               fixed = TRUE)
  parsed <- jsonlite::fromJSON(opts)
  expect_equal(parsed$variables, "A")
  expect_equal(parsed$n, 50)
  expect_equal(parsed$xlim, c(-5, 5))
  expect_equal(parsed$mode, "pull")
  expect_equal(parsed$brush, 0.12)
})

test_that("density control values are validated before reaching JS", {
  v <- density_tool()$validate
  expect_equal(v("variables", " A , B,C "), c("A", "B", "C"))
  expect_error(v("variables", "A, A"), "unique")
  expect_error(v("variables", "A, , B"), "empty")
  expect_equal(v("xlim", list(-5, 5)), c(-5, 5))
  expect_error(v("xlim", c(5, 5)), "xlim")
  expect_equal(v("n", 100), 100)
  expect_error(v("n", 0), "n must")
  expect_error(v("n", 2e6), "n must")
  expect_error(v("n", 10.5), "n must")
  expect_equal(v("mode", "paint"), "paint")
})

test_that("an invalid density control value is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(density_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_xlim = list(0, 10), ctl_variables = "A")
      session$setInputs(ctl_xlim = list(5, 5))
      session$setInputs(ctl_xlim = list(0, 20))
    })
  expect_match(notes, "xlim", all = FALSE)
  expect_equal(sent, list(list(xlim = c(0, 20))))
})

test_that("dcr_density validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_density(variables = c(" a", "b"), n = 50,
                           xlim = c(-5, 5)), "df")
  expect_equal(got$mode, "console")
  expect_equal(got$tool$options$variables, c("a", "b"))
  expect_equal(got$tool$options$n, 50)
  expect_equal(got$tool$options$xlim, c(-5, 5))

  dcr_density()
  expect_equal(got$tool$options$variables, "V1")
  expect_equal(got$tool$options$n, 100)

  expect_error(dcr_density(variables = c("A", "A")), "unique")
  expect_error(dcr_density(xlim = c(5, 5)), "xlim")
  expect_error(dcr_density(xlim = c(10, 0)), "xlim")
  expect_error(dcr_density(n = 0), "n must")
  expect_error(dcr_density(n = 1e7), "n must")
})

test_that("dcr_density_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_density_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("the Density addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_density_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Density")
  expect_equal(unname(row[1, "Description"]), "Density Curve Data Generator")
  expect_equal(unname(row[1, "Interactive"]), "true")
})

test_that("the density shape buttons are stacked, not in a row", {
  html <- htmltools::renderTags(dcr_gadget_ui(density_tool()))$html
  expect_match(html, 'class="dcr-stack"', fixed = TRUE)
  expect_match(html, '(?s)class="dcr-stack".*bell.*flat.*skew', perl = TRUE)
})
