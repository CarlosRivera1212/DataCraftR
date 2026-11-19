test_that("regression_eval() evaluates strings and functions", {
  xs <- seq(0, 10, length.out = 201)
  expect_equal(regression_eval("sin(x)", xs), sin(xs))
  expect_equal(regression_eval("3", xs), rep(3, 201))
  expect_equal(regression_eval(function(x) x^2, xs), xs^2)
  expect_equal(regression_eval("x * pi", xs), xs * pi)
})

test_that("regression_eval() repairs undefined points with a notice", {
  xs <- seq(0, 10, length.out = 201)
  y <- (regression_eval("log(x)", xs))
  expect_true(all(is.finite(y)))
  expect_equal(y[1], y[2])
  expect_match(attr(y, "notice"), "undefined for some x")
})

test_that("regression_eval() errors on bad equations", {
  xs <- seq(0, 10, length.out = 201)
  expect_error(regression_eval("log(-1 - x)", xs), "undefined on the whole")
  expect_error(regression_eval("x +", xs), "Invalid equation")
  expect_error(regression_eval("c(1, 2)", xs), "one value per x")
  expect_error(regression_eval("'a'", xs), "one value per x")
})

test_that("dcr_regression and dcr_regression_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_regression", "dcr_regression_addin") %in% exports))
})

test_that("regression_tool() forwards the regression controls", {
  tool <- regression_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "regression")
  expect_equal(tool$controls,
               c("groups", "active", "target", "mode", "brush", "equation",
                 "level", "shared_x", "xlim", "n", "names"))
})

test_that("the regression UI has its controls, details and actions", {
  html <- htmltools::renderTags(dcr_gadget_ui(regression_tool()))$html
  expect_match(html, 'data-tool="regression"', fixed = TRUE)
  for (id in paste0("ctl_", regression_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_match(html, "<details", fixed = TRUE)
  for (a in c("preset-const", "preset-cone", "preset-rcone", "preset-bowtie",
              "preset-bulge", "fit-y", "resample", "clear")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
})

test_that("regression_options() builds matrices and warns on undefined x", {
  o <- regression_options("x", c("A", "B"), 50, c(0, 10), c(1, 2),
                          c(x = "x", y = "y", group = "g"), TRUE)
  expect_equal(dim(o$f), c(2L, 201L))
  expect_equal(o$s[, 1], c(1, 2))
  expect_equal(o$level, 1)
  expect_equal(o$names$group, "g")
  expect_warning(
    regression_options("log(x)", "A", 50, c(0, 10), 1,
                       c(x = "x", y = "y", group = "group"), TRUE),
    "undefined for some x")
  expect_error(regression_options("x", "A", 1e6, c(0, 10), 1,
                                  c("x", "y", "g"), TRUE), NA)
  expect_error(regression_options("x", c("A", "B"), 1e6, c(0, 10), 1,
                                  c("x", "y", "g"), TRUE), "at most 1e6")
  expect_error(regression_options("x", "A", 5, c(0, 10), -1,
                                  c("x", "y", "g"), TRUE), "sd")
  expect_error(regression_options(c("x", "x^2", "x^3"), c("A", "B"), 5,
                                  c(0, 10), 1, c("x", "y", "g"), TRUE),
               "one per group")
})

test_that("the equation is evaluated on the grid of the new xlim", {
  tool <- regression_tool()
  sent <- list()
  local_mocked_bindings(dcr_notify = function(msg, type) NULL)
  shiny::testServer(
    dcr_gadget_server(tool, "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_xlim = list(0, 10), ctl_equation = "x")
      session$setInputs(ctl_xlim = list(1, 5))
      session$setInputs(ctl_equation = "x^2")
    })
  expect_equal(sent[[2]]$equation$f, seq(1, 5, length.out = 201)^2)
})

test_that("undefined equations warn and still apply; all-undefined is refused", {
  tool <- regression_tool()
  sent <- list()
  notes <- list()
  local_mocked_bindings(dcr_notify = function(msg, type) {
    notes[[length(notes) + 1L]] <<- list(msg = msg, type = type)
  })
  shiny::testServer(
    dcr_gadget_server(tool, "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_xlim = list(0, 10), ctl_equation = "x")
      session$setInputs(ctl_equation = "log(x)")
      session$setInputs(ctl_equation = "log(-1 - x)")
    })
  expect_length(sent, 1L)
  expect_null(attr(sent[[1]]$equation, "notice"))
  expect_true(all(is.finite(sent[[1]]$equation$f)))
  expect_equal(vapply(notes, `[[`, "", "type"), c("warning", "error"))
})

test_that("regression_options() accepts functions and per-group equations", {
  nm <- c(x = "x", y = "y", group = "g")
  o <- regression_options(function(x) x^2, "A", 50, c(0, 10), 1, nm, TRUE)
  expect_equal(o$f[1, ], seq(0, 10, length.out = 201)^2)
  o <- regression_options(list("x", function(x) 10 - x), c("A", "B"), 50,
                          c(0, 10), 1, nm, TRUE)
  xs <- seq(0, 10, length.out = 201)
  expect_equal(o$f[1, ], xs)
  expect_equal(o$f[2, ], 10 - xs)
  expect_error(regression_options("x", "A", 50, c(0, 10), 1, nm, NA),
               "shared_x")
  expect_error(regression_options("x", "A", 50, c(0, 10), 1, nm, "yes"),
               "shared_x")
})

test_that("level_max covers the f range of all groups", {
  nm <- c(x = "x", y = "y", group = "g")
  o <- regression_options(list("x", "100 * x"), c("A", "B"), 50, c(0, 10), 1,
                          nm, TRUE)
  expect_equal(o$level_max, 500)
})

test_that("undefined-x warnings name the group", {
  nm <- c(x = "x", y = "y", group = "g")
  expect_warning(
    regression_options(list("x", "log(x)"), c("A", "B"), 50, c(0, 10), 1,
                       nm, TRUE),
    "group B: the equation is undefined for some x; nearest values were used.",
    fixed = TRUE)
})

test_that("a cleared equation field is ignored silently", {
  tool <- regression_tool()
  sent <- list()
  notes <- list()
  local_mocked_bindings(dcr_notify = function(msg, type) {
    notes[[length(notes) + 1L]] <<- msg
  })
  shiny::testServer(
    dcr_gadget_server(tool, "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      session$setInputs(ctl_xlim = list(0, 10), ctl_equation = "x")
      session$setInputs(ctl_equation = "   ")
    })
  expect_length(sent, 0L)
  expect_length(notes, 0L)
})

test_that("the sidebar defaults: Show sample off, spec example buttons", {
  html <- htmltools::renderTags(dcr_gadget_ui(regression_tool()))$html
  expect_match(html, '<input id="ctl_show" type="checkbox" class="shiny-input-checkbox"/>', fixed = TRUE)
  ex <- regmatches(html, gregexpr('data-equation="[^"]*"', html))[[1]]
  expect_equal(ex, paste0('data-equation="',
                          c("x", "sin(x)", "log(x)", "exp(x/3)", "x^2/10"),
                          '"'))
  expect_match(html, 'aria-label="Pull"', fixed = TRUE)
  expect_match(html, 'aria-label="Error"', fixed = TRUE)
})

test_that("the regression UI loads its tool script", {
  html <- htmltools::renderTags(dcr_gadget_ui(regression_tool()))
  deps <- vapply(html$dependencies, function(d) paste(d$script, collapse = " "), "")
  expect_true(any(grepl("tools/regression.js", deps, fixed = TRUE)))
})
