dcr_palette_colors <- c("#4E79A7", "#F28E2B", "#E15759", "#76B7B2", "#59A14F",
                        "#EDC948", "#B07AA1", "#FF9DA7", "#9C755F", "#BAB0AC")

#' First n colours of the shared Tableau 10 palette
#' @noRd
dcr_palette <- function(n = 10L) {
  if (!is.numeric(n) || length(n) != 1L || n < 1 || n > 10) {
    stop("n must be between 1 and 10.", call. = FALSE)
  }
  dcr_palette_colors[seq_len(n)]
}
