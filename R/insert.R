# Pure decision logic: where to insert and whether to wrap in a chunk.
insert_target <- function(contents, row, path) {
  is_notebook <- grepl("\\.(Rmd|qmd)$", path %||% "", ignore.case = TRUE)
  wrap <- FALSE
  if (is_notebook) {
    # Walk the fences up to the cursor line: a fence line opens a block when
    # outside one (executable if it is ```{...}) and closes it when inside.
    # Only an open executable chunk means "already in R code".
    above <- contents[seq_len(min(row, length(contents)))]
    inside <- FALSE
    executable <- FALSE
    for (line in above[grepl("^\\s*```", above)]) {
      if (inside) {
        inside <- FALSE
      } else {
        inside <- TRUE
        executable <- grepl("^\\s*```\\{", line)
      }
    }
    wrap <- !(inside && executable)
  }
  list(row = row + 1, wrap = wrap)
}

dcr_insert_code <- function(lines) {
  if (!requireNamespace("rstudioapi", quietly = TRUE) ||
      !rstudioapi::isAvailable()) {
    cat(lines, sep = "\n")
    return(invisible(lines))
  }
  ctx <- rstudioapi::getSourceEditorContext()
  if (is.null(ctx) || !nzchar(ctx$id %||% "")) {
    rstudioapi::sendToConsole(paste(lines, collapse = "\n"), execute = TRUE)
    return(invisible(lines))
  }
  cursor <- ctx$selection[[1]]$range$end[["row"]]
  target <- insert_target(ctx$contents, cursor, ctx$path)
  text <- paste0(paste(lines, collapse = "\n"), "\n")
  if (target$wrap) text <- paste0("```{r}\n", text, "```\n")
  if (target$row > length(ctx$contents)) text <- paste0("\n", text)
  rstudioapi::insertText(rstudioapi::document_position(target$row, 1),
                         text, id = ctx$id)
  invisible(lines)
}
