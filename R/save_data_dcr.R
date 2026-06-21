#' @noRd

save_data_dcr <- function(data, type, par = NULL) {
  pre_file = paste0("dcr_", type, "_")
  pre_code = paste0("data_dcr_", type)
  
  tmp_file = tempfile(pattern = pre_file, fileext = ".rds")
  tmp_file = gsub("[\\]", "/", tmp_file)
  
  saveRDS(data, tmp_file)
  
  file_code = paste0(pre_code, ' = readRDS(\"', tmp_file, '\")')
  
  # stp, xmn, xmx
  
  if (type == "hist") {
    #     script_txt = paste0(
    #       "\n",
    #       file_code,
    #       "
    # length(data_dcr_hist)
    # length(data_dcr_hist[[1]])
    # ggplot()+
    #   aes(data_dcr_hist[[1]])+
    #   geom_histogram(binwidth = ",par[1],")+
    #   scale_x_continuous(n.breaks = 10, limits = c(",par[2],", ",par[3],"))+
    #   scale_y_continuous(n.breaks = 10, limits = c(0,",par[4],"))+
    #   theme_bw()
    # "
    #     )
    script_txt = paste0(
      "\n",
      file_code,
      "
length(data_dcr_hist)
length(data_dcr_hist[[1]])
hist(
  data_dcr_hist[[1]],
  breaks = ",
      par[1],
      ",
  xlim = c(",
      par[2],
      ", ",
      par[3],
      "),
  ylim = c(0,",
      par[4],
      ")
)
"
    )
  } else if (type == "scatter") {
    script_txt = paste0(
      "\n",
      file_code,
      "
dim(data_dcr_scatter)
table(data_dcr_scatter$g)

library(ggplot2)
ggplot(data_dcr_scatter) +
  aes(x, y, fill = g) +
  geom_point(size = 3, shape = 21) +
  coord_equal(xlim=c(0,NA), ylim=c(0,NA))+
  theme_bw()
"
    )
  } else if (type == "box") {
    script_txt = paste0(
      "\n",
      file_code,
      "
dim(data_dcr_box)
boxplot(data_dcr_box)
# library(dplyr)
# library(ggplot2)
# data_dcr_box %>%
#   gather() %>%
#   ggplot() +
#   aes(key, value) +
#   geom_boxplot()+
#   theme_bw()
"
    )
  } else if (type == "count") {
    script_txt = paste0(
      "\n",
      file_code,
      "
table(data_dcr_count)
barplot(table(data_dcr_count), beside = T)

# library(ggplot2)
# ggplot(data_dcr_count)+
#   aes(cat, fill=var)+
#   geom_bar(position = 'dodge')+
#   theme_bw()
"
    )
  }
  
  if (rstudioapi::isAvailable()) {
    rstudioapi::insertText(script_txt)
  }

  invisible(tmp_file)
}
