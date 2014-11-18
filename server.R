
OG = readRDS('data//UT_OilGaswRates.rds')


# datadf = readRDS('data/basicCOTSData.rds')
# #dataGPS = readRDS('GPS Data')
# dataIP = readRDS('data/injectionPointsGPS.rds')
# dataPL = readRDS('data/parkingLocations.rds')
# #dataRegions = readRDS('shapefile for region outlines')
# dataLease = readRDS('data/leaseLocations.rds')
# byTruckbyWeek = readRDS('data/forecastByTruckByWeek.rds')
# byCountybyWeek = readRDS('data/forecastByCountyByWeek.rds')
# byTwshpbyWeek = readRDS('data/forecastByTwshpByWeek.rds')
# allFirst7 = readRDS('data/forecastDetail1Week.rds')

#historicalAnalysis
#cotsDLR = readRDS('data/historicalEfficiency.rds')

#shapefiles for CVR Regions and Township Data
#CVRRegions = readRDS('data/CVR_Regions.rds')
#OKKStwp = readRDS('data//OK.rds')

#parkingLots
#parkingLots = readRDS('data/inferredParkingLots.rds')
#liveView = readRDS('data/liveView.rds')
#truckCenterMass = readRDS('data/centermassByTruck.rds')


#precompiled maps
#twpChoro = readRDS('data/twpChoro.rds')

shinyServer(function(input, output, session) {
  
  #simulate some existing tickets based on the OG data ... once for the session
  values = reactiveValues()
  
  observe({
    if(!is.null(input$numLeases)){
      withProgress(message = 'Calculation in progress',
                   detail = 'Creating Datasets...', value = 0, {
                     incProgress(.5)
                     
                  OGSample = sample(1:nrow(OG), input$numLeases)
                  OGsub = OG[OGSample,]#input$numLeases),]
                  
                  #last hour of tickets + 3 days of forecast generation
                  wells = data.frame(WELL_NAME=rep(OGsub$WELL_NAME, 15), misc=1)
                  OGsub = merge(wells, OGsub, by = "WELL_NAME",all.x = T)
                  OGsub = OGsub %.%
                    group_by(WELL_NAME) %.%
                    mutate(pickups=cumsum(rexp(15, OilRate))) %.%
                    filter(pickups<=3) %.%
                    mutate(pickupdate=ymd_hms(format(as.POSIXct(Sys.time()), "%Y-%m-%d %H:%M:%S"))+edays(pickups)-ehours(1))
                  
                  values$OGsub = OGsub
                  values$OGSample = OGSample
                   })
      
    }
    
  })

  
  #some base station positioning (random)
  observe({
    if(!is.null(input$numTrucks) & !is.null(input$numStations) & !is.null(values$OGsub)){
      numTrucks = as.numeric(input$numTrucks)
      numStations = as.numeric(input$numStations)
      
      values$baseStations = data.frame(station=1:round(numTrucks/numStations), 
                                     lat=rnorm(round(numTrucks/numStations), mean(OG$LAT_SURF), sd(OG$LAT_SURF)), 
                                     long=rnorm(round(numTrucks/numStations),  mean(OG$LONG_SURF), sd(OG$LONG_SURF)))
      
      dropOffs = sample(1:nrow(values$baseStations), input$numDropoffs, replace=T)
      values$dropOffPoints = data.frame(dropOff=1:input$numDropoffs, 
                                        lat=rnorm(input$numDropoffs, 0, .5)+values$baseStations[dropOffs, "lat"],
                                        long=rnorm(input$numDropoffs, 0, .5)+values$baseStations[dropOffs, "long"]
      )
      
    }
  })
  
  observe({
    if(!is.null(input$numTrucks) & !is.null(input$numStations)){
      numTrucks = as.numeric(input$numTrucks)
      numStations = as.numeric(input$numStations)
      #some truck baseStation Assignments
      values$trucksStations = data.frame(truckNumber=1:input$numTrucks, station=sample(1:input$numStations, input$numTrucks, replace = T))  
      values$trucksInfo = data.frame(truckNumber=1:input$numTrucks, hoursAvail=12, avgSpeed=30, available=T)
      updateSelectInput(session, "truckAvailable", choices = values$trucksInfo,selected = 1)
      updateSelectInput(session, "truckAssign", choices=values$trucksInfo,selected=1)
    }
  })
  
  observe({
    if(is.null(values$dispatch) & !is.null(values$OGsub)){
      dispatch=dispatchQueue(pickups=values$OGsub, trucksStations = values$trucksStations, baseStations = values$baseStations, 
                             dropOffs=values$dropOffPoints, pickupWindow=4, values$trucksInfo)
      values$dispatch = dispatch
      updateSelectInput(session, "pickupTicket", choices=paste(values$dispatch$dispatch$WELL_NAME, " @ ", values$dispatch$dispatch$pickupdate,sep=""))
    }
    
  })

  observe({
    if(!is.null(values$trucksInfo)){
      updateSelectInput(session, "truckAvailableTF", selected = ifelse(values$trucksInfo$available[input$truckAvailable],"Yes", "No"))
    }
  })
  
  observe({
    
    
  })
  
 ## Live View Map
 output$liveView = renderText({

   withProgress(message = 'Calculation in progress',
                detail = 'Creating Maps...', value = 0, {
                  incProgress(.5)
                  
                  df = data.frame(state=c("utah","utah"), level=c(1,2))
                  #utahMap = choroplethMap(df=df, state = 'state',plotVariable = 'level')
                  baseStations = OSMMap(values$baseStations, popup = paste('Base Station ', values$baseStations$station), colorByFactor = F,color = '#FF0000',layer = 'Base Stations')
                  
                  OGsub = values$OGsub
                  plotVar = (ymd_hms(format(as.POSIXct(Sys.time()), "%Y-%m-%d %H:%M:%S"))-OGsub$pickupdate)/ehours(1)
                  plotVarNorm = (plotVar - min(plotVar))/(max(plotVar) - 
                                                            min(plotVar))
                  
                  
                  OGsub[["colorGray"]] = gray(1-plotVarNorm)
                  pickups = (OSMMap(OGsub, lat="LAT_SURF", long="LONG_SURF", 
                                    popup = paste('<h3>Pickup: ', OGsub$WELL_NAME,"</h3><p>Created: ", OGsub$pickupdate,"</p>Age: ",round(plotVar),"</p>"), 
                                    colorByFactor = F,color = 'colorGray',layer = 'Pickups'))
                  #dropOffs = (OSMMap(values$dropOffPoints, popup = paste('Drop Off ', values$dropOffPoints$dropOff), colorByFactor = F,color = '#0000FF',layer = 'Drop Offs'))
                  
                  print(addLayers(baseStations,pickups),
                        returnText=T, 
                        title="Live Map", 
                        subtitle='Existing Pickups in System', 
                        desc='Darker Points are Older')
                })
   
   
 })
 
 
 ## doing quasi live dispatch... have to push the button to take it forward the next hour to see how things change.
 
 #live ticket generation on top of the existing new ticket data 
 
#  liveTickets = reactiveTimer(intervalMs = 1000, session)
#  observe({
#    liveTickets()
#    #generate any new tickets that come in at
#  })
#  
#  liveDispatch = reactiveTimer(intervalMs = 10000, session)
#  observe({
#    liveDispatch()
#    
#    #any tickets which haven't been assigned, assign them
#  })
  
 #ticketData = reactiveFileReader(intervalMillis = 2000,session = session, filePath = 'data/tickets.rds', readRDS)

 output$existingTickets = renderDataTable({
   windows = seq(min(values$OGsub$pickupdate), max(values$OGsub$pickupdate)+ehours(1), by=ehours(1))+1
   windows = windows[2:length(windows)]
   pickupsWin = values$OGsub %.% 
     group_by(pickupdate) %.%
     mutate(window = which(windows>pickupdate )[1])
   return(
     with(pickupsWin, data.frame(Pickup=WELL_NAME,
                          County=COUNTY,
                          Created=pickupdate,
                          Age=round((ymd_hms(Sys.time())-ymd_hms(pickupdate))/ehours(1),digits = 1),
                          scheduleType=ifelse(window>1, "forecast", "actual")
                          )
      )
   )

   
 })
 
 dispatchQueue=function(pickups, trucksStations, baseStations, dropOffs, pickupWindow = 1, trucksInfo,...,truckAvailability=NULL, futurePickups=NULL,windowsAhead=3){
   
   #dispatch priority
   # tries to assign same lease to same truck if possible
   # closer trucks first
   # lower loaded trucks first
   # tries to minimize amount of time that the ticket spends waiting
   # if there's a truck availability schedule it must obey it
   
   # optimize the queue from start to finish in pickupWindow hours increments 
   # (not all at once)... have to optimize in real time 
   # pickupWindow represents the length of time needed to wait before dispatching tickets (to collect them up)
   # because we don't actually know what's in the future queue, only what's on the plate now
   # however, if we include futurePickups in the decision making we can 
   # optimize considering what's coming in
    windows = seq(min(pickups$pickupdate), max(pickups$pickupdate)+ehours(1), by=ehours(pickupWindow))+1
    windows = windows[2:length(windows)]
    pickupsWin = pickups %.% 
      group_by(pickupdate) %.%
      mutate(window = which(windows>pickupdate )[1])
    
    dispatch = pickupOpt(pickupsWin = subset(pickupsWin, window<=windowsAhead), baseStations = baseStations, 
                         trucksStations = trucksStations,trucksInfo = trucksInfo, dropOffs = dropOffs)
                        
   return(dispatch)
 }

   
 output$queueTable = renderDataTable({
   
   return(with(values$dispatch$dispatch, data.frame(Pickup = WELL_NAME, 
                                               Truck = truckAssigned,
                                               PickupETA = ETAPickup,
                                               DeliveryETA = ETADropOff,
                                               scheduleType=ifelse(window>1, "forecast","actual"))
        ))
   
 })
 
 output$queueTable2 = renderDataTable({
  
  return(with(values$dispatch$dispatch, data.frame(Pickup = WELL_NAME, 
                                                   Truck = truckAssigned,
                                                   PickupETA = ETAPickup,
                                                   DeliveryETA = ETADropOff,
                                                   scheduleType=ifelse(window>1, "forecast","actual"))
  ))
  
})

 output$queueMap= renderText({
   withProgress(message = 'Calculation in progress',
                detail = 'Creating Dispatch Maps...', value = 0, {
                  incProgress(.5)
                  df = data.frame(state=c("utah","utah"), level=c(1,2))
                  utahMap = choroplethMap(df=df, state = 'state',plotVariable = 'level')
                  routeDispatch = dispatchRoute(values$dispatch$dispatch, baseStations, trucksStations, trucksInfo, dropOffs)
                  
                  #jitter the XY a little for easier reading, and change the size of the points
                  routeDispatch$lat = routeDispatch$lat+rnorm(nrow(routeDispatch), 0, .02)
                  #routeDispatch$long = routeDispatch$long+rnorm(nrow(routeDispatch), 0, .02)
                  
                  #pickups = (OSMMap(values$dispatch$dispatch, lat="LAT_SURF", long="LONG_SURF", popup = paste('Pickup ', values$dispatch$dispatch$WELL_NAME), colorByFactor = T,color = 'truckAssigned',layer = 'Pickups'))
                  pickupsLine = (OSMMap(routeDispatch, lat="lat", long="long",color = 'truckAssigned',group="truckAssigned",groupType = "LineString",layer = 'Route'))
                  
                  routeDispatch[["popup"]] = with(routeDispatch, paste("SiteType:", location, "Truck:", truckAssigned))
                  pickupsPoint = (OSMMap(routeDispatch, lat="lat", long="long", popup="popup", color = 'truckAssigned',layer = 'Route stops'))
                  #dropOffs = (OSMMap(values$dropOffPoints, popup = paste('Drop Off ', values$dropOffPoints$dropOff), colorByFactor = F,color = '#0000FF',layer = 'Drop Offs'))
                  #baseStations = OSMMap(values$baseStations, colorByFactor = F,color = '#FF0000',layer = 'Base Stations')
                  incProgress(.25)
#                   values$queueMap = print(addLayers(baseStations, 
#                                                     addLayers(pickupsLine,
#                                                       addLayers(pickups, dropOffs))),
                    values$queueMap = print(addLayers(pickupsLine, pickupsPoint),
                        returnText=T, 
                        title="Base Operations Map", 
                        subtitle='Utah', 
                        desc='Red - Base Stations <br>Green - Pickups<br>Blue - Drop Off Points')
                })
        return(values$queueMap)
                
 })

 output$baseMap = renderText({
   withProgress(message = 'Calculation in progress',
                                 detail = 'Creating Maps...', value = 0, {
                                   incProgress(.5)
                                   df = data.frame(state=c("utah","utah"), level=c(1,2))
                                   utahMap = choroplethMap(df=df, state = 'state',plotVariable = 'level')
                                   baseStations = OSMMap(values$baseStations, popup = paste('Base Station ', values$baseStations$station), colorByFactor = F,color = '#FF0000',layer = 'Base Stations')
                                   pickups = (OSMMap(OG[values$OGSample, ], lat="LAT_SURF", long="LONG_SURF", popup = paste('Pickups ', OG[values$OGSample, "WELL_NAME"]), colorByFactor = F,color = '#00FF00',layer = 'Pickups'))
                                   dropOffs = (OSMMap(values$dropOffPoints, popup = paste('Drop Off ', values$dropOffPoints$dropOff), colorByFactor = F,color = '#0000FF',layer = 'Drop Offs'))
                                   incProgress(.25)
                                   print(addLayers(baseStations,
                                                   addLayers(pickups, dropOffs)),
                                         returnText=T, 
                                         title="Base Operations Map", 
                                         subtitle='Utah', 
                                         desc='Red - Base Stations <br>Green - Pickups<br>Blue - Drop Off Points')
                                 })
 })

output$dispatchStats = renderTable({
  return(t(values$dispatch$dispatchSummary$dispatch))
})
output$dispatchSummaryByTruck = renderDataTable({
  return((values$dispatch$dispatchSummary$dispatchByTruck))
})
output$dispatchSummaryByBaseStation = renderDataTable({
  return((values$dispatch$dispatchSummary$dispatchByBaseStation))
})

output$dispatchByCounty = renderDataTable({
  return((values$dispatch$dispatchSummary$dispatchByCounty))
})

output$dispatchByField = renderDataTable({
  return((values$dispatch$dispatchSummary$dispatchByField))
})
output$dispatchByCompany = renderDataTable({
  return((values$dispatch$dispatchSummary$dispatchByCompany)) 
})

output$trucksInfo = renderDataTable({
  return(values$trucksInfo)
})



})
