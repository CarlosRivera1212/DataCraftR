#' @noRd

#' @noRd
modaldialog_dcr <- function(var_name, input, output){
  showModal(modalDialog(
    textInput("var_name_id", "Variable name in the environment", value = var_name),
    htmlOutput('conf_name_id'),
    footer = tagList(modalButton("Cancel"), actionButton("save_id", "OK"))
  ))
  
  observe({
    req(input$var_name_id)
    
    var_name = input$var_name_id
    
    output$conf_name_id <- renderPrint({
      if(var_name %in% names(.GlobalEnv)){
        tags$h4(
          tags$i(input$var_name_id),
          ' already exist in your environment',
          tags$b('Do you want to overwirte?')
        )
      } else {
        tags$h4('')
      }
    })
  })
}
