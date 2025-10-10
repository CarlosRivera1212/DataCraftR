#' Count Addin for Interactive Count Data Generation
#'
#' @title Count Bar Plot Data Generator
#' 
#' @export

count_dcr <- function(){
  dcr_col = DataCraftR:::palette()
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
          # input_task_button('reset_id', 'Resest all', icon = bs_icon('bootstrap-reboot')),
          # input_task_button('alup_id', 'Top aligment', icon = bs_icon('align-top')),
          # input_task_button('aldw_id', 'Bottom aligment', icon = bs_icon('align-bottom')),
          layout_column_wrap(
            width = 1 / 3,
            fill = T,
            input_task_button('down_id', 'Down', icon = bs_icon('align-bottom'), label_busy = ''),
            input_task_button('mid_id', 'Middle', icon = bs_icon('align-middle'), label_busy = ''),
            input_task_button('up_id', 'Up', icon = bs_icon('align-top'), label_busy = '')
          ),
          
          input_task_button(
            'data_id',
            label = 'Data to environment',
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
        value_name = paste0('data_dcr_', format(Sys.time(), "%Y%m%d%H%M"))
        DataCraftR:::modaldialog_dcr(value_name, input, output)
        name_save(value_name)
      })
    })
    
    
    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Return Data ----
    
    observeEvent(input$data_js, {
      m_count = matrix(input$data_js, input$ncat_id, input$nvar_id, byrow = T)
      
      var_names = paste0('V', 1:input$nvar_id)
      cat_names = paste0('C', 1:input$ncat_id)
      
      data = data.frame(
        var = rep(var_names, colSums(m_count)),
        cat = rep(rep(cat_names, input$nvar_id), m_count)
      )
      
      data_tot(data)
    })
    
    observeEvent(input$save_id, {
      var_name = input$var_name_id
      
      cat('variable: \"', var_name, '\" to environment\n')
      assign(var_name, data_tot(), envir = .GlobalEnv)
      removeModal()
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