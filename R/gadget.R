# Shared gadget shell (layout A): sidebar, canvas + toolbar, stats, footer.

#' Describe a tool for the gadget shell
#'
#' @param name Tool name; matches the JS `DCR.register()` name and the spec.
#' @param title Window title.
#' @param sidebar `function(options)` returning tags; its inputs are named
#'   `ctl_<key>`.
#' @param controls Character vector of control keys forwarded to JS.
#' @param options Named list of initial options passed to the JS tool.
#' @param validate `function(key, value, ...)` run on each `ctl_<key>` value
#'   before it is forwarded; `...` carries `ctl`, a named list (names =
#'   `controls`) of the current raw `ctl_<key>` input values. Returns the value
#'   to send to JS (a `"notice"` attribute is shown as a warning and dropped),
#'   or signals an error (shown as a notification; nothing is sent, so JS keeps
#'   its old value). A condition of class `dcr_skip` drops the value silently.
#' @noRd
new_dcr_tool <- function(name, title, sidebar, controls = character(),
                         options = list(),
                         validate = function(key, value, ...) value) {
  stopifnot(is.character(name), length(name) == 1L,
            is.character(title), length(title) == 1L,
            is.function(sidebar), is.character(controls), is.list(options),
            is.function(validate))
  structure(list(name = name, title = title, sidebar = sidebar,
                 controls = controls, options = options, validate = validate),
            class = "dcr_tool")
}

#' Sidebar section label
#' @noRd
dcr_section <- function(label) {
  htmltools::tags$div(class = "dcr-section-label", label)
}

#' Segmented single-choice input (Shiny binding in shiny-binding.js)
#'
#' @param choices Character vector of values; its names (if any) are the
#'   button labels.
#' @param colors Optional colours drawn as a dot before each label.
#' @param aria_label Accessible name, for when `label` is `NULL`.
#' @param icons Optional named list of inline SVG tags, keyed by choice value;
#'   an icon is drawn before the label, and the button also gets the label as
#'   its `title` and `aria-label`.
#' @noRd
dcr_seg_input <- function(id, label, choices, selected = choices[[1]],
                          colors = NULL, aria_label = label, icons = NULL) {
  tags <- htmltools::tags
  labels <- names(choices) %||% choices
  buttons <- lapply(seq_along(choices), function(i) {
    icon <- icons[[choices[[i]]]]
    tags$button(
      type = "button", `data-value` = choices[[i]],
      `aria-pressed` = if (identical(choices[[i]], selected)) "true" else "false",
      title = if (!is.null(icon)) labels[[i]],
      `aria-label` = if (!is.null(icon)) labels[[i]],
      icon,
      if (!is.null(colors)) {
        tags$span(class = "dcr-dot", style = paste0("background:", colors[[i]]))
      },
      tags$span(labels[[i]])
    )
  })
  tags$div(
    class = "form-group shiny-input-container",
    if (!is.null(label)) tags$label(class = "control-label", `for` = id, label),
    tags$div(id = id, class = "dcr-seg dcr-seg-input", role = "group",
             `aria-label` = aria_label, buttons)
  )
}

#' Several fields read as one input (Shiny binding in shiny-binding.js)
#'
#' The value is an array (unnamed `values`) or an object keyed by
#' `names(values)`; number fields give numbers (or `null` when blank).
#' @noRd
dcr_fields_input <- function(id, label, values, type = c("text", "number")) {
  type <- match.arg(type)
  tags <- htmltools::tags
  keys <- names(values)
  fields <- lapply(seq_along(values), function(i) {
    key <- if (is.null(keys)) NULL else keys[[i]]
    tags$input(type = type, class = "form-control", value = values[[i]],
               step = if (type == "number") "any",
               `data-key` = key,
               `aria-label` = key %||% paste(label, c("min", "max")[i]))
  })
  tags$div(
    class = "form-group shiny-input-container",
    if (!is.null(label)) tags$label(class = "control-label", `for` = id, label),
    tags$div(id = id, class = "dcr-fields dcr-fields-input", fields)
  )
}

#' @noRd
dcr_notify <- function(msg, type = c("message", "warning", "error")) {
  shiny::showNotification(msg, type = match.arg(type))
}

#' Collapsible statistics panel (collapsed by default; toggled in core.js)
#' @noRd
dcr_stats_panel <- function() {
  tags <- htmltools::tags
  tags$div(
    class = "dcr-statsbox",
    tags$button(
      type = "button", id = "dcr-stats-toggle", class = "dcr-sbar",
      `data-dcr-toggle` = "stats", `aria-expanded` = "false",
      `aria-controls` = "dcr-stats-body",
      tags$b("Statistics"),
      tags$span(class = "dcr-sum", "\u00b7 ",
                shiny::textOutput("n_sum", inline = TRUE)),
      tags$span(class = "dcr-chev", `aria-hidden` = "true")
    ),
    tags$div(id = "dcr-stats-body", class = "dcr-stats", hidden = NA,
             shiny::tableOutput("stats"))
  )
}

#' @noRd
dcr_gadget_ui <- function(tool) {
  tags <- htmltools::tags
  options_json <- if (length(tool$options)) {
    as.character(jsonlite::toJSON(tool$options, auto_unbox = TRUE, digits = NA))
  } else {
    "{}"
  }
  icon_btn <- function(action, label, glyph) {
    tags$button(type = "button", class = "btn dcr-icon",
                `data-dcr-action` = action, title = label,
                `aria-label` = label, glyph)
  }
  seed_input <- htmltools::tagQuery(
    shiny::numericInput("seed", NULL, value = sample.int(1e6, 1L),
                        min = 1, step = 1, width = "96px")
  )$find("input")$addAttrs(`aria-label` = "seed")$allTags()
  bslib::page(
    title = paste0("DataCraftR \u00b7 ", tool$title),
    theme = dcr_theme(),
    dcr_dependencies(tool$name),
    tags$div(
      class = "dcr-app",
      tags$div(
        class = "dcr-body",
        tags$aside(
          class = "dcr-sidebar",
          tags$div(class = "dcr-brand", tags$span(class = "dcr-logo"),
                   tool$title, tags$small("\u00b7 DataCraftR")),
          tool$sidebar(tool$options)
        ),
        tags$main(
          class = "dcr-main",
          tags$div(
            class = "dcr-toolbar",
            icon_btn("undo", "Undo (Ctrl+Z)", "\u21b6"),
            icon_btn("redo", "Redo (Ctrl+Shift+Z)", "\u21b7"),
            icon_btn("clear", "Clear", "\u232b"),
            tags$span(class = "dcr-n", shiny::textOutput("n", inline = TRUE))
          ),
          tags$div(id = "tool", class = "dcr-tool", `data-tool` = tool$name,
                   `data-options` = options_json),
          dcr_stats_panel()
        )
      ),
      tags$footer(
        class = "dcr-footer",
        tags$div(class = "dcr-seed", tags$span("seed"), seed_input),
        tags$span(class = "dcr-spacer"),
        shiny::actionButton("cancel", "Cancel", class = "btn-light"),
        tags$button(type = "button", class = "btn btn-primary",
                    `data-dcr-action` = "done", "Done \u00b7 return data")
      )
    )
  )
}

# The seed field if it is a whole number in 1..integer max, else a random one.
dcr_seed <- function(x) {
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x == round(x) && x >= 1 && x <= .Machine$integer.max
  if (ok) as.integer(x) else sample.int(1e6, 1L)
}

#' @noRd
dcr_gadget_server <- function(tool, mode = c("console", "addin"),
                              finish = shiny::stopApp) {
  mode <- match.arg(mode)
  function(input, output, session) {
    lapply(tool$controls, function(key) {
      id <- paste0("ctl_", key)
      shiny::observeEvent(input[[id]], {
        value <- tryCatch({
          ctl <- shiny::isolate(stats::setNames(
            lapply(tool$controls, function(k) input[[paste0("ctl_", k)]]),
            tool$controls))
          v <- tool$validate(key, input[[id]], ctl = ctl)
          notice <- attr(v, "notice", exact = TRUE)
          if (!is.null(notice)) {
            dcr_notify(notice, "warning")
            attr(v, "notice") <- NULL
          }
          list(v)
        }, dcr_skip = function(e) {
          NULL
        }, error = function(e) {
          dcr_notify(conditionMessage(e), "error")
          NULL
        })
        if (!is.null(value)) {
          session$sendInputMessage("tool", stats::setNames(value, key))
        }
      }, ignoreInit = TRUE)
    })

    # Finish exactly once (double-click on Done, Cancel, window closed).
    finished <- FALSE
    finish_once <- function(value) {
      if (finished) return(invisible())
      finished <<- TRUE
      finish(value)
    }

    output$n <- shiny::renderText({
      shiny::req(input$tool, !inherits(input$tool, "dcr_spec_error"))
      paste0("n = ", spec_n(input$tool))
    })
    output$n_sum <- shiny::renderText({
      shiny::req(input$tool, !inherits(input$tool, "dcr_spec_error"))
      paste0("n = ", spec_n(input$tool))
    })
    output$stats <- shiny::renderTable({
      spec <- shiny::req(input$tool)
      shiny::validate(shiny::need(!inherits(spec, "dcr_spec_error"),
                                  spec$message))
      spec_stats(spec)
    }, digits = 2, na = "")

    # Returns the data frame to finish with, or NULL to stay open.
    done <- function(spec) {
      if (inherits(spec, "dcr_spec_error")) {
        dcr_notify(spec$message, "error")
        return(NULL)
      }
      if (spec_is_empty(spec)) {
        dcr_notify("Nothing to return yet", "warning")
        return(NULL)
      }
      df <- dcr_sample(spec, seed = dcr_seed(input$seed))
      dropped <- attr(df, "dropped", exact = TRUE)
      if (length(dropped)) {
        dcr_notify(paste0("Dropped empty variables: ",
                          paste(dropped, collapse = ", ")), "warning")
      }
      if (mode == "addin") {
        used <- attr(df, "dcr_spec", exact = TRUE)
        id <- dcr_save(used)
        dcr_insert_code(dcr_code(id, used))
      }
      df
    }

    shiny::observeEvent(input$tool_done, {
      if (finished) return()
      df <- tryCatch(done(input$tool_done), error = function(e) {
        dcr_notify(conditionMessage(e), "error")
        NULL
      })
      if (!is.null(df)) finish_once(df)
    })

    shiny::observeEvent(input$cancel, finish_once(NULL))
    session$onSessionEnded(function() finish_once(NULL))
  }
}

#' Run a tool as a gadget
#'
#' Console mode returns the data frame (Done) or `NULL` invisibly (Cancel).
#' Addin mode also saves the spec and inserts code.
#' @noRd
run_dcr_gadget <- function(tool, mode = c("console", "addin")) {
  mode <- match.arg(mode)
  viewer <- if (rstudioapi::isAvailable()) {
    shiny::dialogViewer(tool$title, 1000, 720)
  } else {
    shiny::browserViewer()
  }
  res <- shiny::runGadget(dcr_gadget_ui(tool), dcr_gadget_server(tool, mode),
                          viewer = viewer, stopOnCancel = FALSE)
  if (is.null(res)) invisible(NULL) else res
}
