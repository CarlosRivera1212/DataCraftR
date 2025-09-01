#' Histogram Addin for Interactive Data Generation
#'
#' @title Histogram Data Generator
#' @description
#' Launches an interactive Shiny gadget to generate synthetic data using histograms.
#' Users can interactively set bin counts, Y-axis limits, and select variables for visualization.
#' Generated data can be exported to the R environment.
#'
#' @details
#' This gadget integrates Shiny and D3.js for dynamic histogram generation and visualization.
#' Users can adjust:
#' \itemize{
#'   \item The number of variables to display.
#'   \item The variable to draw on the histogram.
#'   \item Number of bins and Y-axis limits.
#'   \item X-axis min and max values, and optionally a random seed.
#' }
#' Interactive buttons allow resetting the histogram, aligning bars to the top or bottom,
#' and exporting the generated data.
#'
#' The D3.js code handles the histogram drawing and interaction, while Shiny manages inputs and server-side data processing.
#'
#' @return
#' Invisibly returns NULL. The main purpose is to launch the interactive gadget.
#' Generated data is assigned to the global environment via the "Data to environment" button as `data_hist_dcr`.
#'
#' @examples
#' \dontrun{
#' # Launch the interactive Histogram addin
#' DataCraftR::histogram_dcr()
#' }
#'
#' @author Carlos Rivera
#' @import shiny
#' @import bslib
#' @import shinyWidgets
#' @importFrom bsicons bs_icon
#' @importFrom rstudioapi sendToConsole insertText
#' @export

histogram_dcr <- function() {
  grp = paste0('V', seq(10))
  dcr_col = DataCraftR:::palette()
  addResourcePath("assets", system.file("assets", package = "DataCraftR"))
  
  ui <- fluidPage(
    # titlePanel('Histogram - '),
    title = 'Histogram',
    
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
    tags$script(src="https://cdn.jsdelivr.net/npm/d3@7"),
    
    sidebarLayout(
      sidebarPanel(
        width = 3,
        tags$h3('Histogram - '),
        
        radioGroupButtons(
          'h_var_id',
          label = 'Drawing variable',
          choices = grp,
          size = 'sm',
          individual = T
        ),
        numericInputIcon(
          'h_nbin_id',
          label = 'Number of bins',
          value = 10,
          min = 1,
          max = 300,
          step = 1,
          width = '100%',
          icon = tags$html(bs_icon('bar-chart-line'))
        ),
        numericInputIcon(
          'h_ymx_id',
          label = 'Y max',
          value = 100,
          min = 1,
          step = 1,
          width = '100%',
          icon = tags$html(bs_icon('rulers'))
        ),
        
        tags$hr(),
        
        
        layout_column_wrap(
          width = 1,
          fill = T,
          input_task_button('h_reset_id', 'Resest all', icon = bs_icon('bootstrap-reboot')),
          input_task_button('h_alup_id', 'Top aligment', icon = bs_icon('align-top')),
          input_task_button('h_aldw_id', 'Bottom aligment', icon = bs_icon('align-bottom')),
          
          input_task_button(
            'h_data_id',
            label = 'Data to environment',
            icon = bs_icon('code-slash'),
            type = 'success',
          ),
          
          dropdown(
            label = tags$html(bs_icon('gear')),
            width = '100%',
            sliderInput(
              'h_nv_id',
              label = 'Numer of Variables',
              min = 1,
              max = 10,
              value = 3,
              step = 1,
              ticks = F
            ),
            numericInputIcon(
              'h_xmn_id',
              label = 'X min',
              value = 0,
              step = 1,
              width = '100%'
            ),
            numericInputIcon(
              'h_xmx_id',
              label = 'X max',
              value = 1,
              step = 1,
              width = '100%'
            ),
            textInput('b_seed_id', label = 'Set seed', placeholder = 123)
            
          ),
          input_task_button(
            'done',
            label = 'Close',
            icon = bs_icon('x-square'),
            type = 'danger'
          )
        ),
        
        
        verbatimTextOutput('print_id')
      ),
      
      mainPanel(
        tags$svg(
          id = 'h_pp_id',
          width = 700,
          height = 700
        ),
        # tags$script(src = "histogram.js"),
        includeScript(system.file("assets/js/histogram.js", package = "DataCraftR"))
      )
    )
  )
  
  server <- function(input, output, session) {
    params = reactiveVal()
    data_tot = reactiveVal()
    
    observeEvent(input$h_nv_id, {
      updateRadioGroupButtons(session, 'h_var_id', choices = grp[seq(input$h_nv_id)])
    })
    
    observe({
      input$h_nbin_id
      input$h_ymx_id
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # JS interaction ----
    
    observe({
      par_inputs = list(
        nv = input$h_nv_id,
        nb = input$h_nbin_id,
        col = dcr_col
      )
      
      session$sendCustomMessage('update_params', par_inputs)
    })
    
    observe({
      par_inputs = list(
        xmn = input$h_xmn_id,
        xmx = input$h_xmx_id,
        ymx = input$h_ymx_id
      )
      
      if (par_inputs$xmn < par_inputs$xmx) {
        session$sendCustomMessage('update_axis', par_inputs)
      } else{
        updateNumericInput(session, 'h_xmx_id', value = input$h_xmn_id + 1)
      }
      
    })
    
    observe({
      par_inputs = list(
        v = input$h_var_id
      )
      session$sendCustomMessage('select_var', par_inputs)
    })
    
    
    observeEvent(input$h_reset_id, {
      session$sendCustomMessage('reset_click', list())
    })
    
    observeEvent(input$h_alup_id, {
      session$sendCustomMessage('alg_up_click', list())
    })
    
    observeEvent(input$h_aldw_id, {
      session$sendCustomMessage('alg_dw_click', list())
    })
    
    observeEvent(input$h_data_id, {
      session$sendCustomMessage('data_click', list())
      
      observeEvent(data_tot(), {
        assign('data_hist_dcr', data_tot(), envir = .GlobalEnv)
        rstudioapi::sendToConsole('data_hist_dcr', execute = F)
        stopApp()
      })
    })
    
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_js, {
      
      h_js = lapply(input$data_js, unlist)
      
      nv = input$h_nv_id
      xmn = input$h_xmn_id
      xmx = input$h_xmx_id
      nb = input$h_nbin_id
      
      stp = (xmx-xmn)/nb
      li = seq(xmn, xmx-stp, stp)
      ls = seq(xmn+stp, xmx, stp)
      
      data = list()
      for (i in seq(nv)) {
        x_i = mapply(function(h, a, b) {
          runif(h, a, b)
        }, h = h_js[[i]], a = li, b = ls)
        
        data[[paste0('V', i)]] = unlist(x_i)
      }
      
      data_tot(data)
    })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Close ----
    observeEvent(input$done, {
      cat(date(), '\n')
      stopApp()
    })
  }
  
  
  # viewer = paneViewer(750)
  viewer = dialogViewer('Histogram DataCraftR', 950, 705)
  runGadget(ui, server, viewer = viewer)
}
