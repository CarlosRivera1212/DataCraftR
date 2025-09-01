#' Boxplot Addin for Interactive Data Generation
#'
#' @title Boxplot Data Generator
#' @description
#' Launches an interactive Shiny gadget to generate synthetic data using either normal or uniform distributions.
#' Users can drag boxplots to define distribution parameters and export the generated data to the R environment.
#'
#' @details
#' This gadget integrates Shiny and D3.js for interactive visualization.
#' Users can adjust the number of variables, sample size, and distribution type.
#' Additional options allow setting initial Y-axis limits and a random seed.
#' The generated data can be exported to the global environment with a single click.
#'
#' The D3.js code handles the boxplot drawing and interaction, while Shiny manages user inputs and server-side data generation.
#'
#' @return
#' Invisibly returns NULL. The main purpose is to launch the interactive gadget.
#' Generated data can be assigned to the global environment via the "Data to environment" button.
#'
#' @examples
#' \dontrun{
#' # Launch the interactive Boxplot addin
#' DataCraftR::boxplot_dcr()
#' }
#'
#' @author Carlos Rivera
#' @import shiny
#' @import bslib
#' @import shinyWidgets
#' @importFrom bsicons bs_icon
#' @importFrom rstudioapi sendToConsole insertText
#' @export

boxplot_dcr <- function() {
  dcr_col = DataCraftR:::palette()
  dcr_col_bg = DataCraftR:::palette(lf = 25)
  addResourcePath("assets", system.file("assets", package = "DataCraftR"))
  
  ui <- fluidPage(
    # titlePanel('Boxplot - '),
    title = 'Boxplot',
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
    tags$script(src="https://cdn.jsdelivr.net/npm/d3@7"),
    
    sidebarLayout(
      sidebarPanel(
        width = 3,
        tags$h3('Boxplot - '),
        
        sliderInput(
          'b_nvar_id',
          label = 'Numer of Variables',
          min = 1,
          max = 10,
          value = 4,
          step = 1
        ),
        
        numericInputIcon(
          'b_nsamp_id',
          'Sample size',
          value = 100,
          min = 10,
          max = 1e6,
          step = 100,
          width = '100%',
          icon = tags$html(bs_icon('123'))
        ),
        
        radioGroupButtons(
          inputId = "b_dis_id",
          label = "Distribution:",
          choiceValues = c('n', 'u'),
          choiceNames = {
            ico_nor = "assets/icons/normal_icon.svg"
            ico_uni = "assets/icons/unif_icon.svg"
            
            list(
              tags$div(tags$img(src = ico_nor), tags$div('Normal')),
              tags$div(tags$img(src = ico_uni), tags$div('Uniform'))
            )
          },
          justified = TRUE
        ),
        
        tags$hr(),
        
        layout_column_wrap(
          width = 1,
          fill = T,
          input_task_button('b_reset_id', 'Reset all', icon = bs_icon('bootstrap-reboot')),
          input_task_button('b_realign_id', 'Align middle', icon = bs_icon('align-middle')),
          
          input_task_button(
            'b_data_id',
            'Data to environment',
            icon = bs_icon('code-slash'),
            type = 'success',
          ),
          
          dropdown(
            label = tags$html(bs_icon('gear'), ''),
            width = '100%',
            
            numericInput('b_iymn_id', 'Initial Y min', 0),
            numericInput('b_iymx_id', 'Initial Y max', 1),
            textInput('b_seed_id', 'Set seed', placeholder = 123)
            
          ),
          input_task_button('done', 'Close', icon = bs_icon('x-square'), type = 'danger')
        ),
        
        verbatimTextOutput('print_id')
      ),
      
      mainPanel(
        tags$svg(
          id = 'b_pp_id',
          width = 700,
          height = 700
        ),
        # tags$script(src = "boxplot.js"),
        includeScript(system.file("assets/js/boxplot.js", package = "DataCraftR"))
      )
    )
  )
  
  server <- function(input, output, session) {
    params = reactiveVal()
    data_tot = reactiveVal()
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # JS interaction ----
    
    observe({
      par_inputs = list(
        nv = input$b_nvar_id,
        cat = paste0('V', seq(input$b_nvar_id)),
        coll = dcr_col,
        colb = dcr_col_bg
      )
      
      params(par_inputs)
      
      session$sendCustomMessage('update_params', params())
    })
    
    observe({
      req(input$b_iymn_id)
      req(input$b_iymx_id)
      par_inputs = list(iymn = input$b_iymn_id, iymx = input$b_iymx_id)
      
      if (par_inputs$iymn < par_inputs$iymx) {
        session$sendCustomMessage('update_y_scale', par_inputs)
      } else{
        updateNumericInput(session, 'b_iymx_id', value = input$b_iymn_id + 1)
      }
    })
    
    observeEvent(input$b_dis_id, {
      session$sendCustomMessage('dist_click', list(dis = input$b_dis_id))
    })
    
    observeEvent(input$b_reset_id, {
      session$sendCustomMessage('rest_click', list())
      updateNumericInput(session, 'b_iymn_id', value = 0)
      updateNumericInput(session, 'b_iymx_id', value = 1)
      updateRadioGroupButtons(session, 'b_dis_id', selected = 'n')
    })
    
    observeEvent(input$b_realign_id, {
      session$sendCustomMessage('realign_click', list())
    })
    
    
    observeEvent(input$b_data_id, {
      session$sendCustomMessage('data_click', list())
      
      observeEvent(data_tot(), {
        assign('data', data_tot(), envir = .GlobalEnv)
      })
    })
    
    
    # observeEvent(input$b_data2_id, {
    #   session$sendCustomMessage('data_click', list())
    #
    #
    #   output$print_id <- renderPrint({
    #     tidyr::tibble(data_tot())
    #   })
    # })
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_js, {
      q_par = sapply(input$data_js[-1], unlist)
      
      nv = input$b_nvar_id
      n = input$b_nsamp_id
      d = input$b_dis_id
      
      try({
        seed = as.numeric(input$b_seed_id)
        set.seed(seed)
      }, silent = T)
      
      data = NULL
      
      if (d == 'n') {
        data = apply(q_par, 1, function(qi) {
          rnorm(n, qi[2], (qi[3] - qi[1]) / (2 * qnorm(0.75)))
        })
      }else if(d == 'u'){
        data = apply(q_par, 1, function(qi) {
          runif(n, qi[2] - (qi[3] - qi[1]), qi[2] + (qi[3] - qi[1]))
        })
      }
      
      data = as.data.frame(data)
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
  viewer = dialogViewer('Boxplot DataCraftR', 950, 705)
  runGadget(ui, server, viewer = viewer)
}
