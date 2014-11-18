## ui.R
library(ggplot2)
library(plyr)
library(dplyr)
library(maps)
library(xtable)
library(lubridate)
library(knitr)
library(zoo)
library(OpenStreetMapR)
library(shiny)
library(shiny-incubator)

# datadf = readRDS('data/basicCOTSData.rds')
# #dataGPS = readRDS('GPS Data')
# dataIP = readRDS('data/injectionPointsGPS.rds')
# dataPL = readRDS('data/parkingLocations.rds')
# #dataRegions = readRDS('shapefile for region outlines')
# dataLease = readRDS('data/leaseLocations.rds')
# byTruckbyWeek = readRDS('data/forecastByTruckByWeek.rds')

OG = readRDS('data/UT_OilGaswRates.rds')

shinyUI(bootstrapPage(title = 'Transportation Analysis Toolbox',
                      fluidRow(
                        column(12,
                               img(src='RA-logo-color.png', style="max-height: 80px"),
                               h1('Multi Objective Optimization Transportation Toolbox'),
                               h4('Powered by ', a(href="http://royaltyanalytics.com", "Royalty Analytics")),
                               hr()
                               )
                        ),
                       fluidRow(
                         column(3,
                                selectInput(inputId = "numTrucks",
                                            label="Number of Trucks",
                                            choices = c(50,100,200,500,1000),
                                            selected = 100),
                                selectInput(inputId = "numStations",
                                            label="Ratio of Trucks to Stations",
                                            choices = c(10,20,30,50),
                                            selected = 10),
                                selectInput(inputId = "numDropoffs",
                                            label="Number of Dropoff points",
                                            choices = c(10,20,30,40,50),
                                            selected = 30),
                                selectInput(inputId = "numLeases",
                                            label="Number of Pickups Serviced",
                                            choices = c(1000,5000,9000),
                                            selected = 1000
                                            )
                                ),
                         column(9, 
                                tabsetPanel(
                                  tabPanel(title = 'Live',
                                           fluidRow(
                                             column(9,
                                                    tags$head(tags$script(src="leaflet.js"),
                                                              tags$link(rel = "stylesheet", type = "text/css", href = "leaflet.css"),
                                                              tags$script(src="jquery-1.10.1.min.js"),
                                                              tags$script(src="jquery-migrate-1.2.1.min.js")
                                                    ),
                                                    
                                                    h3("Live System View"),
                                                    htmlOutput('liveView'),
                                                    h3("Current Tickets"),
                                                    dataTableOutput('existingTickets')
                                                    )
                                             
                                           )
                                  ),
                                  tabPanel(title = 'Dispatch',
                                           tabsetPanel(
                                             tabPanel(title='Current Queue',
                                                      fluidRow(
                                                        column(9,
                                                               h3('Dispatch Map'),
                                                               htmlOutput('queueMap')
                                                        )
                                                        ),
                                                      fluidRow(
                                                        column(6,
                                                               h3('Current Dispatch Queue'),
                                                               dataTableOutput('queueTable')
                                                        ),
                                                        column(6,
                                                               h3('Dispatch Stats'),
                                                               tableOutput('dispatchStats')
                                                        )
                                                      )
                                               ),
                                             tabPanel(title='Dispatch Stats',
                                                      fluidRow(h3('Dispatch Summary Statistics')),
                                                      fluidRow(
                                                        column(9,
                                                               h4('by Truck'),
                                                               dataTableOutput('dispatchSummaryByTruck')
                                                        )
                                                        ),
                                                      fluidRow(
                                                        column(9,
                                                               h4('by Base Station'),
                                                               dataTableOutput('dispatchSummaryByBaseStation')
                                                        )
                                                      ),
                                                      fluidRow(
                                                        column(9,
                                                               h4('by County'),
                                                               dataTableOutput('dispatchByCounty')
                                                        )
                                                      ),
                                                      fluidRow(
                                                        column(9,
                                                               h4('by Field'),
                                                               dataTableOutput('dispatchByField')
                                                        )
                                                      ),
                                                      fluidRow(
                                                        column(9,
                                                               h4('by Company'),
                                                               dataTableOutput('dispatchByCompany')
                                                        )
                                                      )
                                                      ),
                                             tabPanel(title='Resource Availability',
                                                      h3('Truck Availability'),
                                                      fluidRow(
                                                        column(9,
                                                               selectInput(inputId = "truckAvailable",
                                                                           label="Truck Availability to Change",
                                                                           choices = c(0),
                                                                           selected = 0),
                                                                selectInput(inputId = "truckAvailableTF",
                                                                            label="Available?",
                                                                            choices = c("Yes", "No"),
                                                                            selected = "Yes"),
                                                               actionButton(inputId = "btnTruckAvailable", label = "Apply", icon=icon(name = 'calendar'))
                                                            )
                                                        ),
                                                      hr(),
                                                      fluidRow(
                                                        dataTableOutput('trucksInfo')
                                                        )
                                                      
                                              ),
                                             tabPanel(title='Manual Rescheduling',
                                                      h3('Truck Availability'),
                                                      fluidRow(
                                                        column(9,
                                                               selectInput(inputId = "pickupTicket",
                                                                           label="Ticket to Reassign",
                                                                           choices = c(0),
                                                                           selected = 0),
                                                               selectInput(inputId = "truckAssign",
                                                                           label="Truck",
                                                                           choices = c(0),
                                                                           selected = 0),
                                                               submitButton(text = "Apply")
                                                        )
                                                      ),
                                                      hr(),
                                                      fluidRow(
                                                        dataTableOutput('queueTable2')
                                                      )
                                                      
                                             )
                                             )
                                               
                                             
                                           
                                  ),
#                                   tabPanel(title = 'Forecasting',
#                                            
#                                            fluidRow(
#                                              hr(),
#                               
#                                             tabsetPanel(
# #                                               tabPanel(title = 'Load Forecast by County',
# #                                                        column(3),
# #                                                        column(9,
# #                                                               #h3('Forecast by County Map'),
# #                                                               #htmlOutput('forecastByCountyView'),
# #                                                               h3('Forecast by County Table'),
# #                                                               dataTableOutput('forecastByCounty'                                                                               
# #                                                                               ))
# #                                                        
# #                                               ),
# #                                               tabPanel(title = 'Load Forecast by Township',
# #                                                        column(3),
# #                                                        column(9,
# #                                                               #h3('Forecast by Township'),
# #                                                               #htmlOutput('forecastByTownshipView'),
# #                                                               h3('Forecast by Township Table'),
# #                                                               dataTableOutput('forecastByTownship') 
# #                                                               )
# #                                                        ),
#                                               tabPanel(title = 'Load Forecast by Truck',
#                                                        column(3),
#                                                        column(9,
#                                                               h3('Load Forecast by Truck')#,
#                                                               #dataTableOutput('forecastByTruck')
#                                                               )
#                                                        ),
#                                               
#                                               tabPanel(title = '7 Day Detail',
#                                                        column(3),
#                                                        column(9,
#                                                               h3('All Forecast Loads Map'),
#                                                               #htmlOutput('forecastLoadsView'),
#                                                               h3('All Forecast Loads Table')#,
#                                                               #dataTableOutput('forecastLoads')
#                                                               )
#                                                        
#                                               )
#                                             )
#                                              
#                                            )
#                                   ),
                                  tabPanel(title='Resource Allocation',
                                           tabsetPanel(
                                             tabPanel(title='Base Map',
                                                      h3('Pickups, Dropoffs and Base Stations'),
                                                      htmlOutput('baseMap')
                                                      )
                                             )
                                           )
#                                   tabPanel(title = 'Analysis',
#                                            fluidRow(
#                                              column(12,
# #                                                     selectInput(inputId = "historyTimeRegion",
# #                                                                 label = "Timeframe",
# #                                                                 choices = c("Last14Days", "Last30Days","Last90Days","Previous90Days"),
# #                                                                 selected = "Last30Days"
# #                                                      ),
#                                                     tabsetPanel(
#                                                       
#                                                       tabPanel('by Truck',
#                                                                                             h3('Efficiency and Utilization by County'),
#                                                                                             #htmlOutput('historicalCountyView'),
#                                                                                             h3('Data Table for Historical Analysis')#,
#                                                                                             #dataTableOutput('historicalCounty')
#                                                                  ),
#                                                       
#                                                       tabPanel('by Operator',
#                                                                fluidRow(
#                                                                    
#                                                                    column(12,
#                                                                           h3('Truck Level Analysis')#,
#                                                                           #dataTableOutput('historicalTruck')
#                                                                           )
#                                                                            
#                                                                 )
#                                                                ),#end panel
#                                                       tabPanel('by Base Station',
#                                                                fluidRow(
#                                                                  
#                                                                  column(12,
#                                                                         h3('Truck Level Analysis')#,
#                                                                         #dataTableOutput('historicalPL')
#                                                                  )
#                                                                  
#                                                                )
#                                                       ),#end panel
#                                                       tabPanel('All Pickups',
#                                                                fluidRow(
#                                                                  
#                                                                  column(12,
#                                                                         h3('Ticket Level Analysis')#,
#                                                                         #dataTableOutput('historicalTickets')
#                                                                  )
#                                                                  
#                                                                )
#                                                       )#end panel
#                                                                
#                                                     )
#                                                     )
#                                              
#                                              
#                                            ))
                                )#end tabset
                         
                         )#end column
                       )#end row
                       
          
 
))
