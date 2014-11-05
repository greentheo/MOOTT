
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
                  
                  #last 3 days of ticket generation
                  wells = data.frame(WELL_NAME=rep(OGsub$WELL_NAME, 15), misc=1)
                  OGsub = merge(wells, OGsub, by = "WELL_NAME",all.x = T)
                  OGsub = OGsub %.%
                    group_by(WELL_NAME) %.%
                    mutate(pickups=cumsum(rexp(15, OilRate))) %.%
                    filter(pickups<=3) %.%
                    mutate(pickupdate=ymd_hms(Sys.time())+edays(pickups)-edays(3))
                  
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
      values$trucksInfo = data.frame(truckNumber=1:input$numTrucks, hoursAvail=12, avgSpeed=30)
      values$trucksPos = data.frame(truckNumber = 1:input$numTrucks, 
                                    merge(values$trucksStations, values$baseStations, by=""))
    
    }
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
                  plotVar = (ymd_hms(Sys.time())-OGsub$pickupdate)/ehours(1)
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
 
 #live ticket generation on top of the existing new ticket data 
 
 liveTickets = reactiveTimer(intervalMs = 1000, session)
 observe({
   liveTickets()
   #generate any new tickets that come in at
 })
 
 liveDispatch = reactiveTimer(intervalMs = 10000, session)
 observe({
   liveDispatch()
   
   #any tickets which haven't been assigned, assign them
 })
  
 ticketData = reactiveFileReader(intervalMillis = 2000,session = session, filePath = 'data/tickets.rds', readRDS)

 output$existingTickets = renderDataTable({
  
   return(
     with(values$OGsub, data.frame(Pickup=WELL_NAME,
                          County=COUNTY,
                          Created=pickupdate,
                          Age=round((ymd_hms(Sys.time())-ymd_hms(pickupdate))/ehours(1))
                          )
      )
   )

   
 })
 
 dispatchQueue=function(pickups, trucksStations, baseStations, dropoffs, pickupWindow = 1, trucksInfo,...,truckAvailability=NULL, futurePickups=NULL){
   
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
    
    # go window by window and do the dispatch, keep track of the truck hours scheduled and etc.
    trucksInfo[["hoursScheduled"]] = 0
    trucksPos
    for(i in 1:length(windows)){
      pickupsSub = subset(pickupsWin, window=windows[i])
      dist = great_circle_distance(lat1 = trucksStations$)
    }
    
   
 }

   
 output$queueTable = renderDataTable({
   truckQueue=dispatchQueue(pickups=values$OGsub, values$trucksStations, values$baseStations)
   
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

 output$historicalView = renderText({
   counties = map_data("county")
   df = data.frame(state="colorado", county=unique(counties[counties$region=='colorado',"subregion"]),
                   metric=runif(64)
   )
   
   choroMapRed = choroplethMap(df, state='state', county='county',plotVariable='metric',palette = 'red', layerName='Red Layers')
   print(choroMapRed, returnText=T)
 })
 
 output$forecastByCountyView = renderText({
   countySum = summarize(group_by(byCountybyWeek, LSE_LEASE_COUNTY_NAME,LSE_LEASE_STATE, week),
             loads=loads[1],
             truckHours=truckHours[1],
             accuracy=mean(accuracy),
             avgLoadsperWeek=avgLoadsperWeek[1]
   )
   countySum[['county']] = tolower(countySum$LSE_LEASE_COUNTY_NAME)
   countySum[["state"]] = tolower(state.name[match(countySum$LSE_LEASE_STATE, state.abb)])
   countySum[["loadsPlot"]] = with(countySum, cut(loads-avgLoadsperWeek, breaks = c(-Inf,quantile(loads-avgLoadsperWeek, c(.66, .8)),Inf), labels=F))
   
   #2 sets of maps, one with accuracy, one with forecasted load - average, each by week
   #accuracy by Week
#    print(addLayers(choroplethMap(subset(countySum, week==35),  
#                                  plotVariable = 'truckHours', 
#                                  county = 'county',
#                                  palette = 'green', 
#                                  layerName = 'Forecast Truck Hours Next Week'),
   print(
         choroplethMap(subset(countySum, week==35),  
                       plotVariable = 'loadsPlot', 
                       county = 'county',
                       palette = 'red', 
                       layerName = 'Forecast Stress Next Week'
                        ),
         title='Load Forecast By County',
         subtitle='Over Next 7 Days',
         desc='Load Stress in Red',
         returnText=T
   )
   
 })
 output$forecastByCounty = renderDataTable({
   countySum=summarize(group_by(byCountybyWeek, LSE_LEASE_COUNTY_NAME,LSE_LEASE_STATE, week),
             loads=loads[1],
             truckHours=truckHours[1],
             accuracy=mean(accuracy),
             avgLoadsperWeek=avgLoadsperWeek[1],
             stress=loads[1]-avgLoadsperWeek[1]
   )
   subset(countySum, week==35)
             
  })
 
  output$forecastByTownshipView = renderText({
    twshpSum=summarize(group_by(byTwshpbyWeek, township, week),
                       loads=loads[1],
                       truckHours=truckHours[1],
                       accuracy=mean(accuracy),
                       avgLoadsperWeek=avgLoadsperWeek[1],
                       stress=loads[1]-avgLoadsperWeek[1]
    )
    twshpSum = na.omit(subset(twshpSum, week==35))
    twshpSum[["loadsPlot"]] = as.numeric(with(twshpSum, cut(loads-avgLoadsperWeek, breaks = c(-Inf,quantile(loads-avgLoadsperWeek, c(.66, .8)),Inf), labels=F,)))
    
    #2 sets of maps, one with accuracy, one with forecasted load - average, each by week
    #accuracy by Week
#     print(addLayers(choroplethMap(twshpSum,
#                                   state = NULL,
#                                   township = 'township',
#                                   townshipData = OKKStwp,  
#                                   plotVariable = 'truckHours', 
#                                   palette = 'green', 
#                                   layerName = 'Forecast Truck Hours Next Week'),
    print(addLayers(OSMMap(CVRRegions, group='REGION', color='group', groupType="Polygon",layer = "CVR Regions",popup='REGION',static=T),
          choroplethMap(na.omit(subset(twshpSum, township!="")),
                        state = NULL,
                        township = 'township',
                        townshipData = OKKStwp,  
                        plotVariable = 'loads', 
                        palette = 'red', 
                        layerName = 'Forecast Stress Next Week',
                        )
          ),
    title='Load Forecast By Township',
    subtitle='Over Next 7 Days',
    desc='Load Stress in Red',
    returnText=T
    )
  })

  output$forecastByTownship= renderDataTable({
    twshpSum=summarize(group_by(byTwshpbyWeek, township, week),
                        loads=loads[1],
                        truckHours=truckHours[1],
                        accuracy=mean(accuracy),
                        avgLoadsperWeek=avgLoadsperWeek[1],
                        stress=loads[1]-avgLoadsperWeek[1]
    )
    subset(twshpSum, week==35)
    
  })


 output$forecastByTruck = renderDataTable({
   with(subset(byTruckbyWeek, week==35), data.frame(Truck=TRK_TRUCK_NUMBER,
                                                    Loads=loads,
                                                    Hours=round(truckHours),
                                                    #avgLoadsPerWeek=avgLoadsWeek,
                                                    confidence=round(100*confidence))
   )
 })
 
 output$forecastLoads = renderDataTable({
   with(subset(allFirst7, predTimeToNext<=7), data.frame(Lease=LSE_LEASE_NAME.y,
                              Location=LSE_LEASE_LEGAL_DESCR.y,
                              County=LSE_LEASE_COUNTY_NAME,
                              LastPickup=format(TCK_DOT_TURNEDON_DATE, "%Y-%m-%d"),
                              PredictedNext=format(predPickupDate, "%Y-%m-%d"))
   )
 }, options = list(iDisplayLength = 10))
 
 output$forecastLoadsView = renderText({
   leaseAndLocs = merge(subset(allFirst7, predTimeToNext<=7),  dataLease, by.x="LSE_LEASE_NAME.y", by.y="WELL.NAME")
   leaseAndLocs[["popup"]] = with(leaseAndLocs, paste0("<h3>Lease: ",LSE_LEASE_NAME.y, "</h3><h4>Truck: ",
                                                      TRK_TRUCK_NUMBER, "</h4><p>Date Last Picked Up: ", TCK_DOT_TURNEDON_DATE,
                                                      "</p>Time Until Next Pickup: ", predTimeToNext
                                                      )
   )
   plotVar = leaseAndLocs$predTimeToNext
   plotVarNorm = (plotVar - min(plotVar))/(max(plotVar) - 
                                             min(plotVar))
   leaseAndLocs[["colorGray"]] = gray(1-plotVarNorm)
   leaseAndLocs[["group"]] = 1:nrow(leaseAndLocs)
   print(addLayers(OSMMap(CVRRegions, group='REGION', color='group', groupType="Polygon",layer = "CVR Regions",popup='REGION', static=T),
                   OSMMap(leaseAndLocs,lat = 'LATITUDE', long = 'LONGITUDE', color='colorGray',  
                          layer='Forecast Tickets', popup='popup', colorByFactor=F)
   ),
     returnText=T, 
     title="Forecast Loads", 
     subtitle='Next 7 days', 
     desc='Blacker is due sooner.')
   
 })
   
 output$truckCenterView = renderDataTable({
   maxDate = max(datadf$TCK_DOT_TURNEDON_DATE)
   subDate = switch(input$historyTimePL,
          Last14Days=maxDate-edays(14),
          Last30Days=maxDate-edays(30),
          Last90Days=maxDate-edays(90),
          Previous90Days=maxDate-edays(180)
          )
   if(input$historyTimePL=="Previous90Days"){
     maxDate=maxDate-edays(90)
   }
   #calculate center of activity for each truck
   datadfsub = subset(datadf, TCK_DOT_TURNEDON_DATE>=subDate & TCK_DOT_TURNEDON_DATE <=maxDate)
   
   datadfsub = merge(datadfsub, dataLease, by.x="LSE_LEASE_NAME", by.y="WELL.NAME")
   
   datadfsubSum = summarize(group_by(datadfsub, TRK_TRUCK_NUMBER),
             avgLat = mean(LATITUDE),
             avgLong = mean(LONGITUDE))
   
   
   if(input$homesNoHomes=="yes"){
     closestPL = merge(datadfsubSum, dataPL, all=T)#[grep("Home", dataPL$ParkingLocation,invert = T),],all = T)  
   }else{
     closestPL = merge(datadfsubSum, dataPL[grep("Home", dataPL$ParkingLocation,invert = T),],all = T)  
   }
   
   closestPL = merge(closestPL, truckCenterMass, by="TRK_TRUCK_NUMBER")
   closestPL[["distFromPL"]]=with(closestPL, great_circle_distance(CENTERMASS_LAT,CENTERMASS_LONG,lat,long))
   closestPL = filter(group_by(closestPL, TRK_TRUCK_NUMBER),
                      rank(distFromPL, ties.method="first")==1
   )
   
   plMerge = merge(closestPL, parkingLots, by.x="TRK_TRUCK_NUMBER", by.y="TRUCK_ID")
   
   plMerge[["distFromOptimal"]] = with(plMerge, great_circle_distance(X2ND_CANONICAL_LAT, X2ND_CANONICAL_LONG, lat, long))
   plMerge[["avgTripLengthCurr"]] = with(plMerge, great_circle_distance(X2ND_CANONICAL_LAT, X2ND_CANONICAL_LONG, CENTERMASS_LAT, CENTERMASS_LONG))
   plMerge[["pChangeToOpt"]] = with(plMerge, (avgTripLengthCurr-distFromPL)/avgTripLengthCurr)
   
   #merge in CotsDLR info for yearly mileage totals
   truckMilesYear=summarize(group_by(cotsDLR,TRK_TRUCK_NUMBER),
             milesPerYear=sum(milesPart)/((max(CalendarDate)-min(CalendarDate))/edays(1))*365
             )
   truckMilesYear$milesPerYear[ is.infinite(truckMilesYear$milesPerYear)]=0
   plMerge=merge(plMerge, truckMilesYear, "TRK_TRUCK_NUMBER")
   
   arrange(with(plMerge, data.frame(Truck=TRK_TRUCK_NUMBER, 
                            BestPL=ParkingLocation,
                            CurrentPL=NEAREST_MAC_LOT,
                            distance=round(distFromOptimal),
                            #pcntImprove=round(100*pChangeToOpt),
                            #MilesperYearSaved=round((1-pChangeToOpt)*milesPerYear),
                            MilesPerYearDriven=milesPerYear,
                            #avgTripNow=avgTripLengthCurr,
                            #avgTripOpt=distFromPL,
                            Notes=COMMENT)),
           desc(MilesPerYearDriven)
   )
 })
 
 output$leaseTruckAlternatives = renderDataTable({
   maxDate = max(datadf$TCK_DOT_TURNEDON_DATE)
   subDate = maxDate-edays(30)
   lease = input$leaseFilter
   county = input$leaseCounty
#    datadfsub = subset(datadf, TCK_DOT_TURNEDON_DATE>=subDate & TCK_DOT_TURNEDON_DATE <=maxDate 
#                       & LSE_LEASE_NAME==input$leaseFilter)
#    datadfsub = merge(datadfsub, dataLease, by.x="LSE_LEASE_NAME", by.y="WELL.NAME")
#    datadfsubSum = summarize(group_by(datadfsub, TRK_TRUCK_NUMBER),
#                             avgLat = mean(LATITUDE),
#                             avgLong = mean(LONGITUDE))
   
  
   dataLeaseMerge = merge(parkingLots, subset(dataLease,WELL.NAME==lease & COUNTY==county), all = T)
   dataLeaseMerge[["distFromLease"]] = with(dataLeaseMerge, great_circle_distance(X2ND_CANONICAL_LAT,X2ND_CANONICAL_LONG,LATITUDE,LONGITUDE))
   
#    if(input$alternativePriority=="Closest"){
#      return(with( arrange(filter(group_by(dataLeaseMerge,WELL.NAME), 
#                         rank(distFromLease)<10),
#                   WELL.NAME),
#            data.frame(Truck=TRK_TRUCK_NUMBER,
#                       Lease=WELL.NAME,
#                       LeaseLocation=paste(SECTION, TWP, RANGE,"|", LATITUDE, LONGITUDE, sep=' '),
#                       County=COUNTY,
#                       Dist=distFromLease
#                       )
#      ))   
#    }else{
     outTicks = subset(datadf, TCK_DOT_TURNEDON_DATE>="2014-08-28")
     outTicksSummary = summarize(group_by(outTicks, TRK_TRUCK_NUMBER),
                                 loadsCurrent=n())

     
     dataLeaseMergeLoad = merge(dataLeaseMerge, outTicksSummary, by.x="TRUCK_ID", by.y="TRK_TRUCK_NUMBER")
     dataLeaseMergeLoad = merge(dataLeaseMergeLoad, subset(byTruckbyWeek, week==35), by.x="TRUCK_ID", by.y="TRK_TRUCK_NUMBER")
     
      analysisByTruck = summarize(group_by(cotsDLR, TRK_TRUCK_NUMBER),
                                  hoursPerLease=mean(hoursPart)
      )
     dataLeaseMergeLoad = merge(dataLeaseMergeLoad, analysisByTruck, by.x="TRUCK_ID", by.y="TRK_TRUCK_NUMBER")

     return(with( arrange(filter(group_by(dataLeaseMergeLoad,WELL.NAME), 
                                 rank(rank(distFromLease)+rank(loads)+rank(loadsCurrent))<10),
                          WELL.NAME),
                  data.frame(Truck=TRUCK_ID,
                             Lease=WELL.NAME,
                             PLDistFromLease=round(distFromLease),
                             Loads=loadsCurrent,
                             Hours=round(loadsCurrent*hoursPerLease),
                             ForecastLoad=loads,
                             ForecastHours=round(loads*hoursPerLease)
                  )
     ))
     
#    }
   
 }, options = list(iDisplayLength = 10))

 output$leaseTruckLive = renderDataTable({
   outTicks = subset(datadf, TCK_DOT_TURNEDON_DATE>="2014-08-28")
   outTicksSummary = summarize(group_by(outTicks, TRK_TRUCK_NUMBER),
                               loadsCurrent=n())
   
   dataLeaseMergeLoad = merge(outTicksSummary, subset(byTruckbyWeek, week==35), by="TRK_TRUCK_NUMBER")
   
   ## merge historical info about how long it takes to pickup a load for the truck.
   analysisByTruck = summarize(group_by(cotsDLR, TRK_TRUCK_NUMBER),
                               hoursPerLease=mean(hoursPart)
   )
   
   dataLeaseMergeLoad = merge(dataLeaseMergeLoad, analysisByTruck, by="TRK_TRUCK_NUMBER")
   
   return(with( arrange(dataLeaseMergeLoad, 
                               rank(-rank(loads*hoursPerLease)-rank(loadsCurrent*hoursPerLease))),
                data.frame(Truck=TRK_TRUCK_NUMBER,
                           ScheduledLoads=loadsCurrent,
                           ScheduledHours=round(loadsCurrent*hoursPerLease),
                           ForecastLoad=loads,
                           ForecastHours=round(loads*hoursPerLease)
                )
   ))
   
 }, options = list(iDisplayLength = 10))

 output$leaseTruckLoad = renderDataTable({
   if(input$truckFilter=="All"){
     outTicks = subset(datadf, TCK_DOT_TURNEDON_DATE>="2014-08-28" )
     forecastTicks=subset(allFirst7, predTimeToNext<=7)
   }else{
     outTicks = subset(datadf, TCK_DOT_TURNEDON_DATE>="2014-08-28" & TRK_TRUCK_NUMBER==input$truckFilter) 
     forecastTicks = subset(allFirst7, predTimeToNext<=7 & TRK_TRUCK_NUMBER==input$truckFilter)
   }
   rbind(with(outTicks, data.frame(Truck=TRK_TRUCK_NUMBER,
                                   Lease=LSE_LEASE_NAME,
                                   County=LSE_LEASE_COUNTY_NAME,
                                   Load="Current")),
         with(forecastTicks, data.frame(Truck=TRK_TRUCK_NUMBER,
                                        Lease=LSE_LEASE_NAME.y,
                                        County=LSE_LEASE_COUNTY_NAME,
                                        Load="Forecast"))
   )
   
 })

 output$historicalCountyView = renderText({
   if(input$historyTimeRegion=="Last14Days"){
     daysBack = 14
   }else{
     daysBack=30
   }
     analysisByCounty = summarize(group_by(subset(cotsDLR,TCK_DOT_TURNEDON_DATE>(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), LSE_LEASE_COUNTY_NAME, LSE_LEASE_STATE),
                                  bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                                  bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                                  hoursPerLease=mean(hoursPart),
                                  hoursTotal=sum(hoursPart),
                                  utilization=mean(MilesToIP)/mean(milesPart)
     )
     
     analysisByCounty[['county']] = tolower(analysisByCounty$LSE_LEASE_COUNTY_NAME)
     analysisByCounty[["state"]] = tolower(state.name[match(analysisByCounty$LSE_LEASE_STATE, state.abb)])
     analysisByCounty[["cutBPM"]] = cut(analysisByCounty$bpm, breaks = c(-Inf,quantile(analysisByCounty$bpm, seq(0,1,length.out = 4)),Inf), labels = F)
     analysisByCounty[["cutUtility"]] = cut(analysisByCounty$utilization, breaks = c(-Inf,quantile(analysisByCounty$utilization, seq(0,1,length.out = 4)),Inf), labels = F)
     print(addLayers(
       choroplethMap(analysisByCounty, state = 'state',county='county',plotVariable = 'cutBPM',palette = 'red',layerName = 'BarrelsPerMile'),
       choroplethMap(analysisByCounty, state = 'state',county='county',plotVariable = 'cutUtility',palette = 'blue', layerName='%LoadedMiles')
     ),
     returnText=T, 
     title='Efficiency and Utility by County',
     subtitle='Barrels per Mile and %Loaded Miles',
     desc='Darker Colors are more efficient.'
    )
 })

 output$historicalTwnshpView = renderText({
  if(input$historyTimeRegion=="Last14Days"){
    daysBack = 14
  }else{
    daysBack=30
  }
     analysisBytwnshp = summarize(group_by(subset(cotsDLR,TCK_DOT_TURNEDON_DATE>=(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), township),
                                  County=LSE_LEASE_COUNTY_NAME[1],
                                  bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                                  bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                                  hoursPerLease=mean(hoursPart),
                                  hoursTotal=sum(hoursPart),
                                  utilization=mean(MilesToIP)/mean(milesPart)
     )
     analysisBytwnshp[["cutBPM"]] = cut(analysisBytwnshp$bpm, breaks = c(-Inf,quantile(analysisBytwnshp$bpm, seq(0,1,length.out = 4)),Inf), labels = F)
     analysisBytwnshp[["cutUtility"]] = cut(analysisBytwnshp$utilization, breaks = c(-Inf,quantile(analysisBytwnshp$utilization, seq(0,1,length.out = 4)),Inf), labels = F)
#     print(addLayers(
#       choroplethMap(analysisBytwnshp, state = NULL,township='township',plotVariable = 'cutBPM',palette = 'red',layerName = 'BarrelsPerMile',townshipData = OKKStwp),
#       choroplethMap(analysisBytwnshp, state = NULL,township='township',plotVariable = 'cutUtility',palette = 'blue', layerName='%LoadedMiles',townshipData = OKKStwp)
#     ),
#     returnText=T, 
#     title='Efficiency and Utility by Township',
#     subtitle='Barrels per Mile and %Loaded Miles',
#     desc='Darker Colors are more efficient.' 
#     )
      return(twpChoro)
 })

 output$historicalCounty = renderDataTable({
   if(input$historyTimeRegion=="Last14Days"){
     daysBack = 14
   }else{
     daysBack=30
   }
   
     analysisByCounty = summarize(group_by(subset(cotsDLR,TCK_DOT_TURNEDON_DATE>(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), LSE_LEASE_COUNTY_NAME, LSE_LEASE_STATE),
                                  bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                                  bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                                  hoursPerLease=mean(hoursPart),
                                  hoursTotal=sum(hoursPart),
                                  utilization=mean(MilesToIP)/mean(milesPart)
     )
     
     analysisByCounty[['county']] = tolower(analysisByCounty$LSE_LEASE_COUNTY_NAME)
     analysisByCounty[["state"]] = tolower(state.name[match(analysisByCounty$LSE_LEASE_STATE, state.abb)])
     #analysisByCounty[["cutBPM"]] = cut(analysisByCounty$bpm, breaks = c(-Inf,quantile(analysisByCounty$bpm, seq(0,1,length.out = 4)),Inf), labels = F)
     #analysisByCounty[["cutUtility"]] = cut(analysisByCounty$utilization, breaks = c(-Inf,quantile(analysisByCounty$utilization, seq(0,1,length.out = 4)),Inf), labels = F)
     return(analysisByCounty)
   
 })

 output$historicalTwnshp = renderDataTable({
  if(input$historyTimeRegion=="Last14Days"){
    daysBack = 14
  }else{
    daysBack=30
  }
     analysisBytwnshp = summarize(group_by(subset(cotsDLR,TCK_DOT_TURNEDON_DATE>=(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), township),
                                  County=LSE_LEASE_COUNTY_NAME[1],
                                  bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                                  bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                                  hoursPerLease=mean(hoursPart),
                                  hoursTotal=sum(hoursPart),
                                  utilization=mean(MilesToIP)/mean(milesPart)
     )
     return(analysisBytwnshp)
   
 })

 output$historicalPL = renderDataTable({
  
 	dlrpl = merge(cotsDLR,parkingLots, by.x='TRK_TRUCK_NUMBER', by.y='TRUCK_ID') 
	summarize(group_by(dlrpl, NEAREST_MAC_LOT),
                                  bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                                  bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                                  hoursPerLease=mean(hoursPart),
                                  hoursTotal=sum(hoursPart),
                                  utilization=mean(MilesToIP)/mean(milesPart)
	)
 })

 output$historicalTruck = renderDataTable({
   if(input$historyTimeRegion=="Last14Days"){
     daysBack = 14
   }else{
     daysBack=30
   }
   analysisByTruck = summarize(group_by(subset(cotsDLR,TCK_DOT_TURNEDON_DATE>=(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), TRK_TRUCK_NUMBER),
                               bpm=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(milesPart),
                               bph=mean(TCK_DOT_GROSS_GAUGED_BBLS)/mean(hoursPart),
                               hoursPerLease=mean(hoursPart),
                               hoursTotal=sum(hoursPart),
                               utilization=mean(MilesToIP)/mean(milesPart)
   )
   
 })

 output$historicalTickets = renderDataTable({
   if(input$historyTimeRegion=="Last14Days"){
     daysBack = 14
   }else{
     daysBack=30
   }
   
   with(subset(cotsDLR, TCK_DOT_TURNEDON_DATE>=(max(TCK_DOT_TURNEDON_DATE)-edays(daysBack))), 
        data.frame(Lease=LSE_LEASE_NAME,
                   Truck=TRK_TRUCK_NUMBER,
                   Location=LSE_LEASE_LEGAL_DESCR,
                   PickupDate=format(TCK_DOT_TURNEDON_DATE, "%m-%d"),
                   County=LSE_LEASE_COUNTY_NAME,
                   BpM=TCK_DOT_GROSS_GAUGED_BBLS/milesPart,
                   BpH=TCK_DOT_GROSS_GAUGED_BBLS/hoursPart,
                   pcntLoaded=(MilesToIP/milesPart),
                   BbLs=TCK_DOT_GROSS_GAUGED_BBLS,
                   leaseMiles=milesPart
                   )
   )
 })

 #some observers for filter and select box updating


})
