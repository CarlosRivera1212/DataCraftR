#' Scatter Plot Addin for Interactive Data Generation
#'
#' @title Scatter Plot Data Generator
#' @description
#' Launches an interactive Shiny gadget to generate synthetic data by drawing points on a scatter plot.
#' Users can control the number of groups, brush size, and axis limits.
#' The resulting dataset can be exported to rds file with one click.
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
#' A Shiny gadget interface is launched.\
#' The generated data are saved into temporal rds file
#'
#' @examples
#' if (interactive()) {
#' # Launch the interactive Scatter addin
#' scatter_dcr()
#' }
#'
#' @author Carlos Rivera
#' 
#' @import shiny
#' @import bslib
#' @import shinyWidgets
#' @importFrom bsicons bs_icon
#' @importFrom rstudioapi sendToConsole insertText
#'
#' @seealso
#' Other DataCraftR generation tools:
#' \code{\link{boxplot_dcr}}, \code{\link{histogram_dcr}}, \code{\link{count_dcr}}
#' @export

scatter_dcr <- function() {
  grp = stats::setNames(paste0('G', seq(10)), paste0('G', seq(10)))
  # dcr_col = DataCraftR:::palette()
  dcr_col = palette()
  addResourcePath("assets", system.file("assets", package = "DataCraftR"))
  
  ui <- fluidPage(
    # titlePanel('Scatter - '),
    title = 'Scatter',
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
    tags$script(src="https://d3js.org/d3.v7.min.js"),
    
    sidebarLayout(
      sidebarPanel(
        width = 3,
        # tags$h3('Scatter - '),
        
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
          min = 0,
          max = 50,
          value = 10,
          step = 5,
          post = '%'
        ),
        
        tags$hr(),
        
        layout_column_wrap(
          width = 1,
          layout_column_wrap(
            width = 1 / 3,
            fill = T,
            input_task_button('s_reset_id', icon('trash-can'), label_busy = ''),
            input_task_button('s_undo_id', icon('rotate-left'), label_busy = ''),
            input_task_button('s_redo_id', icon('rotate-right'), label_busy = '')
            # input_task_button('s_reset_id', bs_icon('trash3'), label_busy = ''),
            # input_task_button('s_undo_id', bs_icon('arrow-counterclockwise'), label_busy = ''),
            # input_task_button('s_redo_id', bs_icon('arrow-clockwise'), label_busy = '')
          ),
          input_task_button(
            's_data_id',
            label = 'Save Data',
            icon = icon('code'),
            # icon = bs_icon('code-slash'),
            type = 'success',
          ),
        ),
        
        tags$br(),
        dropdown(
          # label = tags$html(bs_icon('gear')),
          label = icon('gear'),
          width = '100%',
          sliderInput(
            's_ngrp_id',
            label = 'Number of Groups',
            min = 1,
            max = 10,
            value = 3,
            step = 1,
            ticks = F
          ),
          numericInput('s_xm_id', 'max x', 1, min = 1),
          numericInput('s_ym_id', 'max y', 1, min = 1),
        ),
        
        
        tags$div(class = 'cards-container', uiOutput('s_txt_id')),

        # input_task_button('done', 'Close', icon = bs_icon('x-square'), type = 'danger'),
        # input_task_button('done', 'Close', icon = icon('remove-circle', lib = 'glyphicon'), type = 'danger'),
        input_task_button('done', 'Close', icon = icon('rectangle-xmark'), type = 'danger'),
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
    data_tot = reactiveVal()
    name_save = reactiveVal(FALSE)
    
    params = reactive({
      req(input$s_ngrp_id, input$s_grp_id, input$s_size_id, input$s_xm_id, input$s_ym_id)
      
      color_idx <- match(input$s_grp_id, names(grp))
      
      list(
        ng = input$s_ngrp_id,
        g = input$s_grp_id,
        c = dcr_col[color_idx],
        s = input$s_size_id/100,
        xm = input$s_xm_id,
        ym = input$s_ym_id
      )
    })
    
    observe({
      updateRadioGroupButtons(session, 's_grp_id', choices = {
        grp[seq(input$s_ngrp_id)]
      })
    })
    
    output$s_txt_id <- renderUI({
      tg = lapply(seq_len(input$s_ngrp_id), function(i){
        gi = paste0('G', i)
        
        tags$div(
          class = 'card',
          style = paste0('background-color: ', dcr_col[i]),
          tags$span(class = 'title', gi),
          tags$span(id = paste0('s_gtxt_', gi), class = 'value', 0)
        )
      })
      
      tagList(tg)
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # JS interaction ----
    
    observeEvent(params(), {
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
    
    observeEvent(input$s_data_id, {
      session$sendCustomMessage("data_click", list())
      
      # observeEvent(data_tot(), {
      #   value_name = paste0('data_dcr_', format(Sys.time(), "%Y%m%d%H%M"))
      #   modaldialog_dcr(value_name, input, output)
      #   name_save(value_name)
      # })
      observeEvent(data_tot(), {
        save_data_dcr(data_tot(), "scatter")
        data_tot(NULL)
        stopApp()
      })
      
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_js, {
      data = data.frame(
        x = unlist(input$data_js$x),
        y = unlist(input$data_js$y),
        g = unlist(input$data_js$g)
      )
      data = data[order(data$g), ]
      rownames(data) = NULL
      data_tot(data)
    })
    
    # observeEvent(input$save_id, {
    #   var_name = input$var_name_id
    #   
    #   cat('variable: \"', var_name, '\" to environment\n')
    #   assign(var_name, data_tot(), envir = .GlobalEnv)
    #   removeModal()
    #   
    #   # if(exists(var_name) & (name_save() != var_name)){
    #   #   modaldialog_dcr(var_name)
    #   # } 
    #   # else {
    #   #   cat('variable: ', var_name, ' to environment\n')
    #   #   assign(var_name, data_tot(), envir = .GlobalEnv)
    #   #   removeModal()
    #   # }
    #   # name_save(var_name)
    # })
    
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