#' Scatter Plot Addin for Interactive Data Generation
#'
#' @title Scatter Plot Data Generator
#' @description
#' Launches an interactive Shiny gadget to generate synthetic data by drawing points on a scatter plot.
#' Users can control the number of groups, brush size, and axis limits, and export the generated data to the R environment.
#'
#' @details
#' This gadget integrates Shiny and D3.js for dynamic scatter plot visualization.
#' Users can adjust:
#' \itemize{
#'   \item The number of groups and the active drawing group.
#'   \item Brush diameter for point drawing.
#'   \item Maximum X and Y axis values.
#' }
#' Interactive buttons allow resetting the plot, undoing/redoing actions, and exporting the generated data.
#'
#' The D3.js code handles drawing and interactivity, while Shiny manages user inputs and server-side data handling.
#'
#' @return
#' Invisibly returns NULL. The main purpose is to launch the interactive gadget.
#' Generated data is available in the `data_tot` reactive and printed as a tibble in the Shiny gadget.
#'
#' @examples
#' \dontrun{
#' # Launch the interactive Scatter addin
#' DataCraftR::scatter_dcr()
#' }
#'
#' @author Carlos Rivera
#' @import shiny
#' @import bslib
#' @import shinyWidgets
#' @importFrom bsicons bs_icon
#' @importFrom dplyr arrange
#' @importFrom tidyr tibble
#' @importFrom rstudioapi sendToConsole insertText
#' @export

scatter_dcr <- function() {
  grp = setNames(seq(10), paste0('G', seq(10)))
  dcr_col = DataCraftR:::palette()
  addResourcePath("assets", system.file("assets", package = "DataCraftR"))
  
  ui <- fluidPage(
    # titlePanel('Scatter - '),
    title = 'Scatter',
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
    tags$script(src="https://cdn.jsdelivr.net/npm/d3@7"),
    
    sidebarLayout(
      sidebarPanel(
        width = 3,
        tags$h3('Scatter - '),
        
        radioGroupButtons(
          's_grp_id',
          'Drawing group',
          
          choices = grp,
          size = 'sm',
          individual = T
        ),
        sliderInput(
          's_size_id',
          'Brush diameter',
          min = 0.0,
          max = 0.5,
          value = 0.1,
          step = 0.05
        ),
        
        tags$hr(),
        
        layout_column_wrap(
          width = 1,
          layout_column_wrap(
            width = 1 / 3,
            fill = T,
            input_task_button('s_reset_id', bs_icon('trash3'), label_busy = ''),
            input_task_button('s_undo_id', bs_icon('arrow-counterclockwise'), label_busy = ''),
            input_task_button('s_redo_id', bs_icon('arrow-clockwise'), label_busy = '')
          ),
          input_task_button(
            's_data_id',
            'Data to environment',
            icon = bs_icon('code-slash'),
            type = 'success',
          ),
          
          dropdown(
            label = tags$html(bs_icon('gear')),
            width = '100%',
            sliderInput(
              's_ngrp_id',
              label = 'Numer of Groups',
              min = 1,
              max = 10,
              value = 3,
              step = 1,
              ticks = F
            ),
            numericInput('s_xm_id', 'max x', 1, min = 1),
            numericInput('s_ym_id', 'max y', 1, min = 1),
          ),
          input_task_button('done', 'Close', icon = bs_icon('x-square'), type = 'danger')
        ),
        
        tags$h3(id = 's_txt_id', 0),
        verbatimTextOutput('print_id')
      ),
      
      mainPanel(
        tags$svg(
          id = 's_pp_id',
          width = 700,
          height = 700
        ),
        
        # tags$script(src = "scatter.js")
        includeScript(system.file("assets/js/scatter.js", package = "DataCraftR"))
      )
    ))
  
  server <- function(input, output, session) {
    params = reactiveVal()
    data_tot = reactiveVal()
    
    observe({
      updateRadioGroupButtons(session, 's_grp_id', choices = {
        grp[seq(input$s_ngrp_id)]
      })
    })
    
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # JS interaction ----
    
    observe({
      par_inputs = list(
        ng = input$s_ngrp_id,
        g = input$s_grp_id,
        c = dcr_col[as.numeric(input$s_grp_id)],
        s = input$s_size_id,
        xm = input$s_xm_id,
        ym = input$s_ym_id
      )
      
      params(par_inputs)
      session$sendCustomMessage('update_params', params())
    })
    
    
    observeEvent(input$s_reset_id, {
      session$sendCustomMessage('reset_click', list())
    })
    
    observeEvent(input$s_undo_id, {
      session$sendCustomMessage('undo_click', list())
    })
    
    observeEvent(input$s_redo_id, {
      session$sendCustomMessage('redo_click', list())
    })
    
    observeEvent(input$s_data_id, {
      session$sendCustomMessage('data_click', list())
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_return, {
      data_js = data.frame(
        x = unlist(input$data_return$x),
        y = unlist(input$data_return$y),
        g = unlist(input$data_return$g)
      )
      data_js = dplyr::arrange(data_js, g)
      data_tot(data_js)
      
      output$print_id <- renderPrint({
        tidyr::tibble(data_js)
      })
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Close ----
    observeEvent(input$done, {
      cat(date(), '\n')
      stopApp()
    })
  }
  
  # viewer = paneViewer(750)
  viewer = dialogViewer('Scatter DataCraftR', 950, 705)
  runGadget(ui, server, viewer = viewer)
}
