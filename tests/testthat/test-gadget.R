test_that("Done with nothing drawn warns and stays open", {
  finished <- FALSE
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console",
                      finish = function(x) finished <<- TRUE), {
      session$setInputs(seed = 1, tool_done = helper_empty_scatter())
      expect_false(finished)
      expect_equal(notes, "Nothing to return yet")
    })
})

test_that("Done returns the sampled data with the seed used", {
  got <- NULL
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console", finish = function(x) got <<- x), {
      session$setInputs(seed = 42, tool_done = helper_histogram())
    })
  expect_s3_class(got, "data.frame")
  expect_equal(nrow(got), 10L)
  expect_equal(dcr_spec(got)$seed, 42)
})

test_that("Done returns a literal scatter exactly", {
  got <- NULL
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console", finish = function(x) got <<- x), {
      session$setInputs(seed = 42, tool_done = helper_scatter())
    })
  want <- dcr_sample(helper_scatter())
  # the spec timestamp has one-second resolution; compare data only
  attr(got, "dcr_spec") <- NULL
  attr(want, "dcr_spec") <- NULL
  expect_equal(got, want)
})

test_that("blank or non-integer seed falls back to a recorded random integer", {
  for (s in list(NA, 2.5, 0)) {
    got <- NULL
    shiny::testServer(
      dcr_gadget_server(helper_tool(), "console", finish = function(x) got <<- x), {
        session$setInputs(seed = s, tool_done = helper_histogram())
      })
    seed <- dcr_spec(got)$seed
    expect_true(seed == round(seed) && seed >= 1 && seed <= 1e6)
  }
})

test_that("dropped histogram variables are reported and Done still finishes", {
  got <- NULL
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console", finish = function(x) got <<- x), {
      session$setInputs(seed = 1,
                        tool_done = helper_histogram(rbind(c(1, 1), c(0, 0))))
    })
  expect_equal(names(got), "V1")
  expect_equal(notes, "Dropped empty variables: V2")
})

test_that("addin mode saves the spec and inserts code", {
  withr::local_envvar(R_USER_DATA_DIR = withr::local_tempdir())
  inserted <- NULL
  got <- NULL
  local_mocked_bindings(dcr_insert_code = function(lines) inserted <<- lines)
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "addin", finish = function(x) got <<- x), {
      session$setInputs(seed = 1, tool_done = helper_scatter())
    })
  expect_length(list.files(dcr_store_dir(), pattern = "[.]rds$"), 1L)
  expect_length(inserted, 3L)
  expect_match(inserted[2], '^df <- dcr_load\\("scatter_')
  expect_s3_class(got, "data.frame")
})

test_that("addin save errors are shown and the gadget stays open", {
  finished <- FALSE
  notes <- character()
  local_mocked_bindings(
    dcr_notify = function(msg, type) notes <<- c(notes, msg),
    dcr_save = function(spec, time = Sys.time()) stop("Could not save to x: denied"),
    dcr_insert_code = function(lines) stop("must not insert")
  )
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "addin",
                      finish = function(x) finished <<- TRUE), {
      session$setInputs(seed = 1, tool_done = helper_scatter())
      expect_false(finished)
    })
  expect_equal(notes, "Could not save to x: denied")
})

test_that("an invalid spec from JS is shown as an error and the gadget stays open", {
  finished <- FALSE
  notes <- list()
  local_mocked_bindings(dcr_notify = function(msg, type) {
    notes[[length(notes) + 1L]] <<- list(msg = msg, type = type)
  })
  bad <- dcr_spec_input_handler(
    jsonlite::toJSON(list(tool = "scatter", xlim = c(0, 10), ylim = c(0, 10),
                          groups = c("A", "A"),
                          points = list(x = list(), y = list(), group = list())),
                     auto_unbox = TRUE), NULL, "tool_done")
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console",
                      finish = function(x) finished <<- TRUE), {
      session$setInputs(seed = 1, tool = bad, tool_done = bad)
      expect_false(finished)
      expect_error(output$stats, "groups must be unique")
    })
  expect_equal(notes, list(list(msg = "groups must be unique.", type = "error")))
})

test_that("a double Done in addin mode saves and inserts once", {
  withr::local_envvar(R_USER_DATA_DIR = withr::local_tempdir())
  n_insert <- 0L
  n_finish <- 0L
  local_mocked_bindings(dcr_insert_code = function(lines) n_insert <<- n_insert + 1L)
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "addin",
                      finish = function(x) n_finish <<- n_finish + 1L), {
      session$setInputs(seed = 1, tool_done = helper_scatter())
      session$setInputs(tool_done = helper_histogram())
    })
  expect_length(list.files(dcr_store_dir(), pattern = "[.]rds$"), 1L)
  expect_equal(n_insert, 1L)
  expect_equal(n_finish, 1L)
})

test_that("errors while finishing are shown and the gadget stays open", {
  withr::local_envvar(R_USER_DATA_DIR = withr::local_tempdir())
  finished <- FALSE
  notes <- character()
  local_mocked_bindings(
    dcr_notify = function(msg, type) notes <<- c(notes, msg),
    dcr_insert_code = function(lines) stop("no editor")
  )
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "addin",
                      finish = function(x) finished <<- TRUE), {
      session$setInputs(seed = 1, tool_done = helper_scatter())
      expect_false(finished)
    })
  expect_equal(notes, "no editor")
})

test_that("closing the window finishes with NULL once", {
  calls <- list()
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console",
                      finish = function(x) calls <<- c(calls, list(x))), {
      expect_length(calls, 0L)
    })
  expect_equal(calls, list(NULL))

  calls <- list()
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console",
                      finish = function(x) calls <<- c(calls, list(x))), {
      session$setInputs(cancel = 1)
    })
  expect_equal(calls, list(NULL))
})

test_that("Cancel finishes with NULL", {
  got <- "unset"
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console", finish = function(x) got <<- x), {
      session$setInputs(cancel = 1)
    })
  expect_null(got)
})

test_that("stats and n follow the tool input", {
  shiny::testServer(
    dcr_gadget_server(helper_tool(), "console", finish = function(x) NULL), {
      session$setInputs(tool = helper_scatter())
      expect_equal(output$n, "n = 3")
      expect_match(output$stats, "<table")
    })
})

test_that("ctl_ inputs are forwarded to the tool", {
  tool <- new_dcr_tool("scatter", title = "Scatter",
                       sidebar = function(options) shiny::tagList(),
                       controls = c("mode", "xlim"), options = list())
  sent <- list()
  shiny::testServer(
    dcr_gadget_server(tool, "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- list(id = inputId, msg = message)
      }
      # initial values come from the same options as the JS tool: not sent
      session$setInputs(ctl_mode = "spray", ctl_xlim = c(0, 10))
      session$setInputs(ctl_mode = "erase")
      session$setInputs(ctl_xlim = c(-5, 5))
    })
  expect_equal(sent, list(list(id = "tool", msg = list(mode = "erase")),
                          list(id = "tool", msg = list(xlim = c(-5, 5)))))
})

test_that("dcr_dependencies points at files on disk", {
  deps <- dcr_dependencies()
  expect_length(deps, 2L)
  for (d in deps) {
    dir <- d$src$file
    expect_true(dir.exists(dir))
    expect_true(all(file.exists(file.path(dir, c(d$script, d$stylesheet)))))
  }
  expect_equal(deps[[1]]$version, "7.9.0")
  expect_equal(deps[[2]]$version, "0.4.0")
  expect_equal(utils::tail(deps[[2]]$script, 1), "shiny-binding.js")
})

test_that("the gadget UI has the shell parts", {
  html <- htmltools::renderTags(dcr_gadget_ui(helper_tool()))$html
  expect_match(html, 'class="dcr-tool"', fixed = TRUE)
  expect_match(html, 'data-tool="scatter"', fixed = TRUE)
  expect_match(html, 'data-dcr-action="done"', fixed = TRUE)
  expect_match(html, 'data-dcr-action="undo"', fixed = TRUE)
  expect_match(html, 'id="cancel"', fixed = TRUE)
  expect_match(html, 'id="seed"', fixed = TRUE)
})

test_that("a tool's validate() transforms control values or blocks them", {
  tool <- new_dcr_tool("scatter", title = "Scatter",
                       sidebar = function(options) shiny::tagList(),
                       controls = c("lim", "mode"),
                       validate = function(key, value, ...) {
                         if (key == "lim") check_range(unlist(value), "lim") else value
                       })
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
      session$setInputs(ctl_lim = list(0, 10), ctl_mode = "a")
      session$setInputs(ctl_lim = list(-5, 5))
      session$setInputs(ctl_lim = list(5, 5))
      session$setInputs(ctl_mode = "b")
    })
  expect_equal(sent, list(list(lim = c(-5, 5)), list(mode = "b")))
  expect_equal(notes, list(list(
    msg = "lim must be two finite numbers with the first less than the second.",
    type = "error")))
})

test_that("validate() gets the other controls; a notice warns and is dropped", {
  tool <- new_dcr_tool("scatter", title = "Scatter",
                       sidebar = function(options) shiny::tagList(),
                       controls = c("a", "other"),
                       validate = function(key, value, ...) {
                         dots <- list(...)
                         if (key != "a") return(value)
                         out <- paste(value, dots$ctl$other)
                         attr(out, "notice") <- "careful"
                         out
                       })
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
      session$setInputs(ctl_other = "Z", ctl_a = "init")
      session$setInputs(ctl_a = "v")
    })
  expect_equal(sent[[1]], list(a = "v Z"))
  expect_null(attr(sent[[1]]$a, "notice"))
  expect_equal(notes[[1]], list(msg = "careful", type = "warning"))
})

test_that("a dcr_skip condition from validate() sends nothing and is silent", {
  tool <- new_dcr_tool("scatter", title = "Scatter",
                       sidebar = function(options) shiny::tagList(),
                       controls = c("a"),
                       validate = function(key, value, ...) {
                         if (identical(value, "skip")) {
                           stop(structure(class = c("dcr_skip", "error", "condition"),
                                          list(message = "skip", call = NULL)))
                         }
                         value
                       })
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
      session$setInputs(ctl_a = "init")
      session$setInputs(ctl_a = "skip")
    })
  expect_equal(sent, list())
  expect_equal(notes, list())
})

test_that("new_dcr_tool() validate defaults to the identity", {
  expect_equal(helper_tool()$validate("x", list(1, 2)), list(1, 2))
  expect_error(new_dcr_tool("a", "A", function(o) NULL, validate = "no"))
})

test_that("dcr_seg_input() marks the selected choice and colours", {
  html <- as.character(dcr_seg_input("ctl_active", "Group",
                                     c(A = "1", B = "2"), selected = "2",
                                     colors = c("#4E79A7", "#F28E2B")))
  expect_match(html, 'id="ctl_active"', fixed = TRUE)
  expect_match(html, 'class="dcr-seg dcr-seg-input"', fixed = TRUE)
  expect_match(html, 'data-value="1" aria-pressed="false"', fixed = TRUE)
  expect_match(html, 'data-value="2" aria-pressed="true"', fixed = TRUE)
  expect_match(html, "background:#F28E2B", fixed = TRUE)
  expect_match(html, ">B</span>", fixed = TRUE)
})

test_that("dcr_seg_input() draws icons and keeps the labels accessible", {
  icon <- htmltools::tags$svg(class = "ic")
  html <- as.character(dcr_seg_input("ctl_mode", NULL,
                                     c(Pull = "pull", Paint = "paint"),
                                     icons = list(pull = icon),
                                     aria_label = "Mode"))
  expect_match(html, '<svg class="ic"></svg>', fixed = TRUE)
  expect_match(html, 'title="Pull"', fixed = TRUE)
  expect_match(html, 'aria-label="Pull"', fixed = TRUE)
  expect_match(html, ">Paint</span>", fixed = TRUE)
  expect_no_match(html, 'title="Paint"', fixed = TRUE)
})

test_that("dcr_fields_input() builds keyed or unkeyed fields", {
  html <- as.character(dcr_fields_input("ctl_xlim", "x", c(0, 10), type = "number"))
  expect_match(html, 'id="ctl_xlim"', fixed = TRUE)
  expect_match(html, 'class="dcr-fields dcr-fields-input"', fixed = TRUE)
  expect_equal(lengths(regmatches(html, gregexpr('type="number"', html))), 2L)
  expect_match(html, 'value="10"', fixed = TRUE)
  html <- as.character(dcr_fields_input("ctl_names", NULL,
                                        c(x = "x", y = "y", group = "g")))
  expect_match(html, 'data-key="group"', fixed = TRUE)
  expect_match(html, 'aria-label="group"', fixed = TRUE)
  expect_match(html, 'type="text"', fixed = TRUE)
})
