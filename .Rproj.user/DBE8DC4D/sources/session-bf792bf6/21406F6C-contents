#' @importFrom RcppColors hsl

# ggthemes::ggthemes_data$calc$colors$value
palette <- function(n = 10, name = 'default', lf = 0) {
  if (name == 'neon') {
    palette = c(
      "#00E5FF",
      "#FF00B8",
      "#76FF03",
      "#FFEA00",
      "#FF6D00",
      "#C51162",
      "#651FFF",
      "#00C853",
      "#FF1744",
      "#121212"
    )
  } else if (name == 'pastel') {
    palette = c(
      "#FF6F61",
      "#A8E6CF",
      "#FFF176",
      "#4FC3F7",
      "#BA68C8",
      "#ECEFF1",
      "#FFAB91",
      "#81D4FA",
      "#D1C4E9",
      "#C8E6C9"
    )
  } else if (name == 'tropical') {
    palette = c(
      "#FF3D00",
      "#FFD600",
      "#64DD17",
      "#00B8D4",
      "#2962FF",
      "#AA00FF",
      "#FF9100",
      "#00C853",
      "#FF5252",
      "#00E5FF"
    )
  } else {
    h = c(186, 317, 93, 55, 26, 199, 0, 145, 71, 323)
    s = rep(100, 10)
    l = c(50, 50, 50, 50, 50, 50, 66, 70, 50, 70)

    hex = sapply(seq(10), function(i) {
      RcppColors::hsl(h[i], s[i], l[i]+lf)
    })

    palette = hex
  }

  if (n > 10) {
    stop('n <= 10')
  } else {
    palette = palette[1:n]
  }

  return(palette)
}
