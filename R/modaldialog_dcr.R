modaldialog_dcr <- function(var_name){
  showModal(modalDialog(
    textInput("var_name_id", "Variable name in the environment", value = var_name),
    htmlOutput('conf_name_id'),
    footer = tagList(modalButton("Cancel"), actionButton("save_id", "OK"))
  ))
}
