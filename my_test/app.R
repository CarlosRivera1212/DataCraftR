library(shiny)
library(bslib)
library(shinyWidgets)
library(bsicons)
library(dplyr)
library(tidyr)

options(shiny.autoreload = TRUE)

grp = paste0('V', seq(10))
# dcr_col = palette()
dcr_col = DataCraftR:::palette()
addResourcePath("assets", system.file("assets", package = "DataCraftR"))

ui <- fluidPage(
  title = 'Density',
  tags$link(rel = 'stylesheet', type = 'text/css', href = 'assets/css/dcr_style.css'),
  tags$script(src="https://cdn.jsdelivr.net/npm/d3@7"),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      tags$h3('Density - '),
      
      radioGroupButtons(
        'd_var_id',
        label = 'Drawing variable',
        choices = grp[1:3],
        size = 'sm',
        individual = T
      ),
      # radioGroupButtons(
      #   inputId = "d_dis_id",
      #   label = "Distribution:",
      #   choiceValues = c("n", "u"),
      #   choiceNames = {
      #     ico_nor <- "assets/icons/normal_icon.svg"
      #     ico_uni <- "assets/icons/unif_icon.svg"
      #     
      #     list(
      #       tags$div(tags$img(src = ico_nor), tags$div("Normal")),
      #       tags$div(tags$img(src = ico_uni), tags$div("Uniform"))
      #     )
      #   },
      #   justified = TRUE
      # ),
      
      # numericInputIcon(
      #   'h_ymx_id',
      #   label = 'Y max',
      #   value = 100,
      #   min = 1,
      #   step = 1,
      #   width = '100%',
      #   icon = tags$html(bs_icon('rulers'))
      # ),
      
      tags$hr(),
      
      
      layout_column_wrap(
        width = 1,
        fill = T,
        input_task_button('d_alup_id', 'Top aligment', icon = bs_icon('align-top')),
        input_task_button('d_aldw_id', 'Bottom aligment', icon = bs_icon('align-bottom')),
        input_task_button('d_reset_id', 'Resest all', icon = bs_icon('bootstrap-reboot')),
        
        input_task_button(
          'd_data_id',
          label = 'Save Data',
          icon = bs_icon('code-slash'),
          type = 'success',
        ),
        
        dropdown(
          label = tags$html(bs_icon('gear')),
          width = '100%',
          sliderInput(
            'd_nv_id',
            label = 'Number of Variables',
            min = 1,
            max = 10,
            value = 3,
            step = 1,
            ticks = F
          ),
          sliderInput(
            'd_step_id',
            label = 'Number of brakes',
            min = 1,
            max = 10,
            value = 5,
            step = 1,
            ticks = F
          ),
          textInput('d_seed_id', label = 'Set seed', placeholder = 123),
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
        id = 'd_pp_id',
        width = 700,
        height = 700
      ),
      tags$script(src = "density.js"),
      # includeScript(system.file("assets/js/density.js", package = "DataCraftR"))
    )
  )
)

server <- function(input, output, session) {
  data_tot = reactiveVal()
  data_par = reactiveVal()
  
  # params = reactiveValues()
  # 
  # observeEvent(input$h_nv_id, {
  #   updateRadioGroupButtons(session, 'h_var_id', choices = grp[seq(input$h_nv_id)])
  # })
  # 
  # observe({
  #   input$h_nbin_id
  #   input$h_ymx_id
  # })
  # 
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # Load settings ----
  observeEvent(input$d_nv_id, {
    updateRadioGroupButtons(
      session, "d_var_id", choices = grp[seq(input$d_nv_id)]
    )
  })
  
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # JS interaction ----

  observe({
    par_inputs = list(
      nv = input$d_nv_id,
      stp = input$d_step_id,
      # points = seq(0,1,l=input$d_step_id),
      col = dcr_col
    )

    session$sendCustomMessage('update_params', par_inputs)
  })
  
  observe({
    par_inputs = list(
      v = input$d_var_id
    )
    session$sendCustomMessage('update_v', par_inputs)
  })
  
  observeEvent(input$d_alup_id, {
    session$sendCustomMessage('alup', list())
  })
  observeEvent(input$d_aldw_id, {
    session$sendCustomMessage('aldw', list())
  })
  observeEvent(input$d_reset_id, {
    session$sendCustomMessage('reset', list())
  })
  
  # 
  # observe({
  #   par_inputs = list(
  #     xmn = input$h_xmn_id,
  #     xmx = input$h_xmx_id,
  #     ymx = input$h_ymx_id
  #   )
  #   
  #   if (par_inputs$xmn < par_inputs$xmx) {
  #     session$sendCustomMessage('update_axis', par_inputs)
  #   } else{
  #     updateNumericInput(session, 'h_xmx_id', value = input$h_xmn_id + 1)
  #   }
  #   
  # })
  # 
  # 
  # 
  observeEvent(input$d_data_id, {
    session$sendCustomMessage('data_click', list())

    observeEvent(data_tot(), {
      save_data_dcr(data_tot(), "dens", data_par())
      data_tot(NULL)
      # stopApp()
    })
  })


  # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # Return Data ----

  observeEvent(input$data_js, {

    data_js = lapply(input$data_js, unlist)
    print(data_js)
    # 
    # nv = input$h_nv_id
    # xmn = input$h_xmn_id
    # xmx = input$h_xmx_id
    # ymx = input$h_ymx_id
    # nb = input$h_nbin_id
    # 
    # stp = (xmx-xmn)/nb
    # # li = seq(xmn, xmx-stp, stp)
    # # ls = seq(xmn+stp, xmx, stp)
    # 
    # if (nchar(input$h_seed_id) > 0) {
    #   set.seed(as.numeric(input$h_seed_id))
    # }
    # 
    # data = list()
    # 
    # for (i in seq(nv)) {
    #   h = h_js[[i]]
    #   cent = stp * which(h>0)
    # 
    #   if(any(h!=0)){
    #     # x_i = mapply(function(h, a, b) {
    #     #   stats::runif(h, a, b)
    #     # }, h = h_js[[i]], a = li, b = ls)
    #     #
    #     # data[[paste0('V', i)]] = unlist(x_i)
    # 
    #     x_i = mapply(function(h, c) {
    #       stats::runif(h, c-stp, c)
    #     }, h = h[h>0], c = cent, SIMPLIFY = F)
    #     data[[paste0('V', i)]] = unlist(x_i)
    #   }
    # }
    # 
    # if(length(data)>0){
    #   data_tot(data)
    #   # data_par(c(stp, xmn, xmx, ymx))
    #   data_par(c(nb, xmn, xmx, ymx))
    # }
  })

  # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  # # Close ----
  # observeEvent(input$done, {
  #   # cat(date(), '\n')
  #   stopApp()
  # })
}


# viewer = paneViewer(750)
# viewer = dialogViewer('Histogram DataCraftR', 950, 705)
shinyApp(ui, server)
