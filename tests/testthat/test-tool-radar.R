test_that("dcr_radar and dcr_radar_addin are exported", {
  exports <- getNamespaceExports("DataCraftR")
  expect_true(all(c("dcr_radar", "dcr_radar_addin") %in% exports))
})

test_that("radar_tool() forwards the radar controls", {
  tool <- radar_tool()
  expect_s3_class(tool, "dcr_tool")
  expect_equal(tool$name, "radar")
  expect_equal(tool$controls,
               c("groups", "active", "target", "variables", "ranges", "n",
                 "integers", "group_name"))
})

test_that("the radar UI has its controls, details and actions", {
  rendered <- htmltools::renderTags(dcr_gadget_ui(radar_tool()))
  html <- rendered$html
  expect_match(html, 'data-tool="radar"', fixed = TRUE)
  for (id in paste0("ctl_", radar_tool()$controls)) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_match(html, "<details", fixed = TRUE)
  for (a in c("preset-tight", "preset-medium", "preset-wide", "same-all",
              "resample", "clear")) {
    expect_match(html, paste0('data-dcr-action="', a, '"'), fixed = TRUE)
  }
  expect_match(html, 'aria-label="Mean"', fixed = TRUE)
  expect_match(html, 'aria-label="Spread"', fixed = TRUE)
  # one min/max pair per default variable (5 variables -> 10 fields)
  rng <- sub('.*(<div id="ctl_ranges".*?)<details.*', "\\1", html)
  expect_equal(lengths(regmatches(rng, gregexpr("<input", rng))), 10L)
})

test_that("radar_initial() is deterministic, in range and distinct per group", {
  ranges <- cbind(c(0, -5, 10), c(10, 5, 110))
  a <- radar_initial(c("A", "B"), ranges)
  expect_equal(a, radar_initial(c("A", "B"), ranges))
  expect_equal(dim(a$mean), c(2L, 3L))
  expect_equal(dim(a$sd), c(2L, 3L))
  expect_true(all(a$mean >= rep(ranges[, 1], each = 2) &
                    a$mean <= rep(ranges[, 2], each = 2)))
  expect_equal(a$sd, matrix(rep(0.1 * (ranges[, 2] - ranges[, 1]), each = 2),
                            2L))
  expect_false(isTRUE(all.equal(a$mean[1, ], a$mean[2, ])))
  # formula: group 1, variable 1 sits at mid + 0.25 * width
  expect_equal(a$mean[1, 1], 5 + 0.25 * 10)
  # one group is fine
  expect_equal(dim(radar_initial("A", ranges)$mean), c(1L, 3L))
})

test_that("radar options reach the JS tool as JSON", {
  opts <- radar_options(c("V1", "V2", "V3"), c("A"), 50, c(0, 10), FALSE,
                        "group")
  html <- htmltools::renderTags(dcr_gadget_ui(radar_tool(opts)))$html
  o <- regmatches(html, regexpr('data-options="[^"]*"', html))
  o <- gsub("&quot;", '"', sub('^data-options="(.*)"$', "\\1", o), fixed = TRUE)
  parsed <- jsonlite::fromJSON(o, simplifyVector = FALSE)
  expect_equal(unlist(parsed$groups), "A")
  expect_equal(unlist(parsed$variables), c("V1", "V2", "V3"))
  expect_length(parsed$ranges, 3L)
  expect_equal(unlist(parsed$ranges[[1]]), c(0, 10))
  expect_length(parsed$mean, 1L)
  expect_length(parsed$mean[[1]], 3L)
  expect_length(parsed$sd[[1]], 3L)
  expect_equal(parsed$n, 50)
  expect_false(parsed$integers)
  expect_equal(parsed$group_name, "group")
  expect_equal(parsed$target, "mean")
})

test_that("dcr_radar validates its arguments and runs in console mode", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- list(tool = tool, mode = mode)
    "df"
  })
  expect_equal(dcr_radar(), "df")
  expect_equal(got$mode, "console")
  o <- got$tool$options
  expect_equal(o$variables, c("V1", "V2", "V3", "V4", "V5"))
  expect_equal(o$groups, c("A", "B"))
  expect_equal(o$n, 50)
  expect_equal(dim(o$ranges), c(5L, 2L))
  expect_equal(o$ranges[, 1], rep(0, 5))
  expect_equal(dim(o$mean), c(2L, 5L))
  expect_false(o$integers)
  expect_equal(o$group_name, "group")

  dcr_radar(variables = c(" a", "b", "c"), range = list(c(0, 1), c(0, 5), c(1, 9)))
  expect_equal(got$tool$options$variables, c("a", "b", "c"))
  expect_equal(unname(got$tool$options$ranges[3, ]), c(1, 9))
  dcr_radar(n = 5e5)   # 2 groups x 5e5 = 1e6: allowed
  expect_equal(got$tool$options$n, 5e5)

  expect_error(dcr_radar(range = list(c(0, 1), c(0, 1))), "one pair per variable")
  expect_error(dcr_radar(variables = c("a", "b")), "3 to 12")
  expect_error(dcr_radar(group_name = "V1"), "differ")
  expect_error(dcr_radar(groups = c("A", "B", "C"), n = 4e5), "at most 1e6")
  expect_error(dcr_radar(range = c(5, 5)), "range")
  expect_error(dcr_radar(n = 0), "whole number")
  expect_error(dcr_radar(groups = c("A", "A")), "unique")
  expect_error(dcr_radar(integers = NA), "integers")
})

test_that("dcr_radar_addin runs in addin mode and returns invisibly", {
  got <- NULL
  local_mocked_bindings(run_dcr_gadget = function(tool, mode) {
    got <<- mode
    data.frame(x = 1)
  })
  expect_invisible(res <- dcr_radar_addin())
  expect_null(res)
  expect_equal(got, "addin")
})

test_that("radar control values are validated before reaching JS", {
  v <- radar_tool()$validate
  expect_equal(v("groups", " A , B,C "), c("A", "B", "C"))
  expect_error(v("groups", "A, A"), "unique")
  expect_equal(v("variables", " a , b,c "), c("a", "b", "c"))
  expect_error(v("variables", "a, b"), "3 to 12")
  expect_error(v("variables", "a, a, b"), "unique")
  expect_equal(v("n", 20), 20)
  expect_error(v("n", 0), "whole number")
  expect_equal(v("group_name", " g "), "g")
  expect_error(v("group_name", "a, b"), "single")
  expect_error(v("group_name", "v1", ctl = list(variables = "v1, v2, v3")),
               "differ")
  expect_error(v("variables", "a, b, group", ctl = list(group_name = "group")),
               "group column")
  expect_equal(v("variables", "a, b, c", ctl = list(group_name = "group")),
               c("a", "b", "c"))
  expect_equal(v("target", "spread"), "spread")
  r <- v("ranges", list(0, 10, -5, 5, 1, 2))
  expect_equal(r, list(c(0, 10), c(-5, 5), c(1, 2)))
  expect_error(v("ranges", list(0, 10, 5, 5, 1, 2)), "ranges\\[2\\]")
  expect_error(v("ranges", list(0, 10, "a", 5, 1, 2)), "numeric")
  expect_error(v("ranges", list(0, 10, NULL, 5, 1, 2)), "numeric")
  expect_error(v("ranges", list(0, 10, 1)), "pairs")
})

test_that("an invalid ctl_ranges is notified and not forwarded", {
  sent <- list()
  notes <- character()
  local_mocked_bindings(dcr_notify = function(msg, type) notes <<- c(notes, msg))
  shiny::testServer(
    dcr_gadget_server(radar_tool(), "console", finish = function(x) NULL), {
      session$sendInputMessage <- function(inputId, message) {
        sent[[length(sent) + 1L]] <<- message
      }
      # The first setInputs is swallowed by ignoreInit (it only seeds the
      # observer), so nothing is validated or sent for it.
      session$setInputs(ctl_ranges = list(0, 10, 0, 10, 0, 10))
      session$setInputs(ctl_ranges = list(0, 10, 7, 3, 0, 10))
      session$setInputs(ctl_ranges = list(0, 10, "x", 3, 0, 10))
      session$setInputs(ctl_ranges = list(0, 10, -1, 12, 0, 10))
    })
  expect_length(notes, 2L)
  expect_match(notes[1], "ranges[2]", fixed = TRUE)
  expect_length(sent, 1L)
  expect_equal(sent[[1]], list(ranges = list(c(0, 10), c(-1, 12), c(0, 10))))
})

test_that("the Radar addin is registered", {
  dcf <- read.dcf(system.file("rstudio", "addins.dcf", package = "DataCraftR"))
  row <- dcf[dcf[, "Binding"] == "dcr_radar_addin", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(unname(row[1, "Name"]), "Radar profiles")
  expect_equal(unname(row[1, "Description"]),
               "Draw group profiles on a radar chart and insert code to sample them")
  expect_equal(unname(row[1, "Interactive"]), "true")
})
