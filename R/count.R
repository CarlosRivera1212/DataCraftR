#' Count Addin for Interactive Count Data Generation
#'
#' @title Count Bar Plot Data Generator
#'
#' @description
#' Opens an interactive Shiny gadget that allows users to visually generate
#' **count-based categorical data** by adjusting bar heights in a D3.js bar plot.
#'
#' Users can control the number of variables, number of categories per variable,
#' and the maximum count value for the bars. 
#' The resulting dataset can be exported to rds file with one click.
#'
#' This tool is designed to support data simulation for teaching, demos, and
#' prototyping of discrete categorical count structures.
#'
#' @details
#' **JavaScript integration** (via `count.js`) is used to capture user interactions,
#' dynamically update counts, and return the generated data to R.
#'
#' Data are returned as a data frame with two factors:
#' \itemize{
#'   \item \code{var}: Variable identity (e.g. V1, V2, ...)
#'   \item \code{cat}: Category identity (e.g. C1, C2, ...)
#' }
#'
#' @return
#' A Shiny gadget interface is launched.\
#' The generated data are saved into temporal rds file
#'
#' @examples
#' \dontrun{
#' # Launch the interactive count generator
#' DataCraftR::count_dcr()
#' }
#'
#' @author Carlos Rivera
#' 
#' @import shiny
#' @import bslib
#' @import shinyWidgets
#' @importFrom bsicons bs_icon
#'
#' @seealso
#' Other DataCraftR generation tools:
#' \code{\link{boxplot_dcr}}, \code{\link{histogram_dcr}}, \code{\link{scatter_dcr}}
#' @export

count_dcr <- function(){
  dcr_col = palette()
  addResourcePath("assets", system.file("assets", package = "DataCraftR"))
  
  ui <- fluidPage(
    title = 'Count',
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
    tags$script(src="https://d3js.org/d3.v7.min.js"),
    
    sidebarLayout(
      sidebarPanel(
        width = 3,
        tags$h3('Count - '),
        
        sliderInput(
          "nvar_id",
          label = "Number of Variables",
          min = 1,
          max = 10,
          value = 3,
          step = 1
        ),
        sliderInput(
          "ncat_id",
          label = "Number of Categories",
          min = 1,
          max = 10,
          value = 3,
          step = 1
        ),
        numericInputIcon(
          'ymx_id',
          label = 'Y max',
          value = 10,
          min = 1,
          step = 1,
          width = '100%',
          icon = tags$html(bs_icon('rulers'))
        ),
        
        
        
        tags$hr(),
        
        
        layout_column_wrap(
          width = 1,
          fill = T,
          input_task_button('reset_id', 'Resest all', icon = bs_icon('bootstrap-reboot')),
          input_task_button('alup_id', 'Top aligment', icon = bs_icon('align-top')),
          input_task_button('aldw_id', 'Bottom aligment', icon = bs_icon('align-bottom')),
          # layout_column_wrap(
          #   width = 1 / 3,
          #   fill = T,
          #   input_task_button('down_id', 'Down', icon = bs_icon('align-bottom'), label_busy = ''),
          #   input_task_button('mid_id', 'Middle', icon = bs_icon('align-middle'), label_busy = ''),
          #   input_task_button('up_id', 'Up', icon = bs_icon('align-top'), label_busy = '')
          # ),
          
          input_task_button(
            'data_id',
            label = 'Save Data',
            icon = bs_icon('code-slash'),
            type = 'success',
          ),
          
          # dropdown(
          #   label = tags$html(bs_icon('gear')),
          #   width = '100%',
          #   textInput('seed_id', label = 'Set seed', placeholder = 123)
          #   
          # ),
          
          tags$hr(),
          
          input_task_button(
            'done',
            label = 'Close',
            icon = bs_icon('x-square'),
            type = 'danger'
          )
        ),
        
        tags$div(class = 'cards-container', uiOutput('s_txt_id'))
      ),
      
      mainPanel(
        tags$svg(
          id = 'c_pp_id',
          width = 700,
          height = 700
        ),
        
        # tags$script(src = "count.js")
        includeScript(system.file("assets/js/count.js", package = "DataCraftR"))
      )
    ))
  
  server <- function(input, output, session) {
    data_tot = reactiveVal()
    name_save = reactiveVal()
    
    params = reactive({
      req(input$nvar_id, input$ncat_id)
      
      list(
        nv = input$nvar_id,
        cat = paste0('C', seq_len(input$ncat_id)),
        col = dcr_col
      )
    })
    
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # JS interaction ----
    
    observeEvent(params(), {
      session$sendCustomMessage('update_params', params())
    })
    
    observeEvent(input$ymx_id, {
      session$sendCustomMessage('update_y', input$ymx_id)
    })
    
    observeEvent(input$down_id, {
      session$sendCustomMessage('align', 'down')
    })
    
    observeEvent(input$mid_id, {
      session$sendCustomMessage('align', 'mid')
    })
    
    observeEvent(input$up_id, {
      session$sendCustomMessage('align', 'up')
    })
    
    observeEvent(input$data_id, {
      session$sendCustomMessage("data_click", NA)
      
      observeEvent(data_tot(), {
        save_data_dcr(data_tot(), "count")
        data_tot(NULL)
        # stopApp()
      })
    })
    
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_js, {
      m_count = matrix(input$data_js, input$ncat_id, input$nvar_id, byrow = T)
      
      var_names = paste0('V', 1:input$nvar_id)
      cat_names = paste0('C', 1:input$ncat_id)
      
      pre_var = rep(var_names, colSums(m_count))
      pre_cat = apply(m_count, 2, function(x){rep(cat_names, x)})
      
      data = data.frame(
        var = factor(pre_var, levels = var_names, ordered = T),
        cat = factor(unlist(pre_cat), levels = cat_names, ordered = T)
      )
      
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
  viewer = dialogViewer('Count DataCraftR', 950, 705)
  runGadget(ui, server, viewer = viewer)
}