#' Calculate distances over the curvature of the earth
#' @param lat1 a vector of lattitudes to start at
#' @param long1 a vector of longitudes to start at
#' @param lat2 a vector of lattitues to end at
#' @param long2 a vector of longitudes to end at
#' @return numeric vector of distances
#' @export
great_circle_distance <- function(lat1, long1, lat2, long2) {
  lat1=lat1*pi/180
  lat2=lat2*pi/180
  long1=long1*pi/180
  long2=long2*pi/180
  
  a <- sin(0.5 * (lat2 - lat1))
  b <- sin(0.5 * (long2 - long1))
  7926 * asin(sqrt(a * a + cos(lat1) * cos(lat2) * b * b))
}

#' Dispatch a set of scheduled pickups
#' @param data a list of various data items returned from baseData, or passed in via JSON 
#' @return list with a data.frame of dispatches
#' @export
dispatchQueue=function(data, pickupWindow=1,windowsAhead=1){
  

  #pickups, trucksStations, baseStations, dropOffs, pickupWindow = 1, trucksInfo,...,truckAvailability=NULL, futurePickups=NULL,windowsAhead=3){
  
   windows = seq(min(data$OGsub$pickupdate), max(data$OGsub$pickupdate)+ehours(1), by=ehours(pickupWindow))+1
   windows = windows[2:length(windows)]
   pickupsWin = data$OGsub %.% 
     group_by(pickupdate) %.%
     mutate(window = which(windows>pickupdate )[1])
   
  
   dispatch = pickupOpt(pickupsWin = subset(pickupsWin, window<=windowsAhead), baseStations = data$baseStations, 
                        trucksStations = data$trucksStations,trucksInfo = data$trucksInfo, dropOffs = data$dropOffPoints)

  return(dispatch)
}

#' A function which helps create a pickupDropOffPair Matrix
#' @param pickups a dataframe containing pickups to be made
#' @param baseData the list object returned from baseData()
#' @export
pickupDropOffs = function(pickupsWin, dropOffs, baseStations){
  pickupDropoffPairs = pickupsWin %.%
    group_by(WELL_NAME) %.%
    summarize(dropOff=dropOffs[which.min(great_circle_distance(LAT_SURF, LONG_SURF, dropOffs$lat, dropOffs$long)), "dropOff"],
              dropOffDist=min(great_circle_distance(LAT_SURF[1], LONG_SURF[1], dropOffs$lat, dropOffs$long)),
              dropOffSpeed=rnorm(1, 30, 5),
              station=baseStations[which.min(great_circle_distance(LAT_SURF, LONG_SURF, baseStations$lat, baseStations$long)), "station"],
              stationDist=min(great_circle_distance(LAT_SURF[1], LONG_SURF[1], baseStations$lat, baseStations$long))
    )
  return(pickupDropoffPairs)
}

#' A function which does the actual dispatching and metric calculations
#' @param pickupsWin 
#' @param baseStations
#' @param trucksStations
#' @param trucksInfo
#' @param dropOffs
#' @param truckLocation
pickupOpt = function(pickupsWin, baseStations, trucksStations, trucksInfo, dropOffs,...,truckLocation=NULL){
  
#   withProgress(message = 'Dispatch Optimization in progress',
#                detail = 'Creating DispatchSchedule...', value = 0, {
#                  incProgress(.01)
                 
  pickupsWin=pickupsWin %.%
    arrange(ymd_hms(pickupdate)) %.% 
    mutate(day = format(ymd_hms(pickupdate), "%d"))
    
  pickupDropoffPairs = pickupDropOffs(pickupsWin, dropOffs, baseStations)
  
  
  weightedPoints=merge(pickupsWin, pickupDropoffPairs,by="WELL_NAME")
  weightedPoints=merge(weightedPoints, dropOffs, by="dropOff")
  weightedPoints=merge(weightedPoints, baseStations, by="station")
  
  #use the pickups to wells, the dropoffs and base stations to find the weighted center of activity (for use in new pickups)
  weightedPointsDF = data.frame(lat=c(weightedPoints$LAT_SURF, weightedPoints$lat.x, weightedPoints$lat.y[1:round(nrow(weightedPoints)/5)]), 
                                long=c(weightedPoints$LONG_SURF, weightedPoints$long.x,weightedPoints$long.y[1:round(nrow(weightedPoints)/5)]),
                                station=c(rep(weightedPoints$station,2), weightedPoints$station[1:round(nrow(weightedPoints)/5)])
                     )
  
  weightedPointsDF = weightedPointsDF %.%
    group_by(station) %.%
    summarise(centerLat=mean(lat),
              centerLong=mean(long))
  
 
  
  ## assign to first closest truck with availability... calculate where all trucks are and whether they are full or not.
  ## use these estimates to do the routing
  
  pickupTickets = data.frame(pickupsWin, truckAssigned=0,ETAPickup=max(pickupsWin$pickupdate), 
                             ETADropOff=max(pickupsWin$pickupdate), assignedDropOff=0, 
                             mileageToPickup=0, mileageToDropOff=0)
  if(is.null(truckLocation)){
    truckLocation = data.frame(trucksStations, nextLocation=0, nextAvailableLocation=0, 
                               ETANext=min(pickupsWin$pickupdate), ETANextAvailable=min(pickupsWin$pickupdate))
  }
  truckHours = data.frame(trucksStations, trucksInfo, hours=0)
  
  uniqueWells = pickupsWin %.%
    group_by(WELL_NAME) %.%
    summarize(LAT_SURF=LAT_SURF[1],
              LONG_SURF=LONG_SURF[1])
  
  locationTable = data.frame(id=1:(nrow(baseStations)+nrow(dropOffs)+nrow(uniqueWells)), 
                             type=c(rep("baseStation", nrow(baseStations)), rep("dropOff", nrow(dropOffs)),
                                    rep("pickup", nrow(uniqueWells))),
                             name=c(baseStations$station, dropOffs$dropOff, as.character(uniqueWells$WELL_NAME)),
                             lat=c(baseStations$lat, dropOffs$lat, uniqueWells$LAT_SURF),
                             long=c(baseStations$long, dropOffs$long, uniqueWells$LONG_SURF)
  )
  
  location = merge(subset(locationTable, type=="baseStation"), trucksStations,by.x="name", by.y="station")
  truckLocation$nextAvailableLocation=merge(truckLocation, location, by="truckNumber")$id
  
#   incProgress(.24)
  for(i in 1:nrow(pickupTickets)){
#     incProgress(i*.5/nrow(pickupTickets))
    #print(i)
    #update all truck's theoretical positions and ETA's in truckLocation
      #where the truck was last
    if(i>1){
      truckLast = pickupTickets %.%
        filter(truckAssigned != 0) %.%
        group_by(truckAssigned) %.%
        summarize(lastPickup=pickupdate[tail(c(1, which(ETAPickup<pickupTickets$pickupdate[i])), n=1)],
                 lastDropOff= pickupdate[tail(c(1, which(ETADropOff<pickupTickets$pickupdate[i])), n=1)],
                 nextPickup=pickupdate[c(which(ETAPickup>pickupTickets$pickupdate[i]), length(pickupdate))[1] ],
                 nextDropOff=pickupdate[c(which(ETADropOff>pickupTickets$pickupdate[i]), length(pickupdate))[1] ]
                 ) 
      
      truckLastLocation = plyr::ddply(truckLast, .variables = c("truckAssigned"), function(x){
        #print(x)
        if(x$lastDropOff==x$nextDropOff){
          #then next location is baseStation, so is nextAvailable Location  
          nextLocation=subset(locationTable, name==trucksStations$station[x$truckAssigned] & type=="baseStation")
          nextAvailableLocation=nextLocation
          lastLocation=subset(locationTable, name==subset(pickupTickets, pickupdate==x$lastDropOff)$assignedDropOff &
                                             type=="dropOff")  
                                                          
          ETANext=subset(pickupTickets, pickupdate==x$lastDropOff)$ETADropOff+
            duration(great_circle_distance(lastLocation$lat, lastLocation$long, nextLocation$lat, nextLocation$long)/
            trucksInfo$avgSpeed[ x$truckAssigned], "hours")
          ETANextAvailable=ETANext
          
          return(data.frame(truckNumber=x$truckAssigned, 
                            nextLocation=nextLocation$id,
                            nextAvailableLocation=nextAvailableLocation$id ,
                            ETANext= ETANext,
                            ETANextAvailable= ETANextAvailable))  
        }
        if(x$nextPickup > x$lastPickup & x$lastDropOff==x$lastPickup){
          #then the truck has just dropped off the load and is heading to the next pickup
          nextLocation=subset(locationTable, name==as.character(subset(pickupTickets, pickupdate==x$nextPickup)$WELL_NAME) )
          nextAvailableLocation=subset(locationTable, name==subset(pickupTickets, pickupdate==x$nextPickup)$assignedDropOff & type=="dropOff")
          lastLocation=subset(locationTable, name==subset(pickupTickets, pickupdate==x$lastDropOff)$assignedDropOff &
                                type=="dropOff")  
          
          ETANext=subset(pickupTickets, pickupdate==x$lastDropOff)$ETADropOff+
            duration(great_circle_distance(lastLocation$lat, lastLocation$long, nextLocation$lat, nextLocation$long)/
                       trucksInfo$avgSpeed[ x$truckAssigned], "hours")
          ETANextAvailable=subset(pickupTickets, pickupdate==x$nextDropOff)$ETADropOff
          return(data.frame(truckNumber=x$truckAssigned, 
                            nextLocation=nextLocation$id,
                            nextAvailableLocation=nextAvailableLocation$id ,
                            ETANext= ETANext,
                            ETANextAvailable= ETANextAvailable))  
        }
        if(x$nextDropOff == x$lastPickup){
          #then the truck has just picked up the load and is en route to the dropoff
          nextLocation=subset(locationTable, name==subset(pickupTickets, pickupdate==x$lastPickup)$assignedDropOff & type=="dropOff" )
          nextAvailableLocation=nextLocation
          lastLocation=subset(locationTable, name==subset(pickupTickets, pickupdate==x$lastPickup)$assignedDropOff &
                                type=="dropOff")  
          
          ETANext=subset(pickupTickets, pickupdate==x$lastPickup)$ETAPickup+
            duration(great_circle_distance(lastLocation$lat, lastLocation$long, nextLocation$lat, nextLocation$long)/
                       trucksInfo$avgSpeed[ x$truckAssigned], "hours")
          ETANextAvailable=ETANext
          return(data.frame(truckNumber=x$truckAssigned, 
                            nextLocation=nextLocation$id,
                            nextAvailableLocation=nextAvailableLocation$id ,
                            ETANext= ETANext,
                            ETANextAvailable= ETANextAvailable)) 
        }
      })
      
      truckLocation[truckLastLocation$truckAssigned, c("nextLocation","nextAvailableLocation","ETANext", "ETANextAvailable")] = 
        truckLastLocation[ ,c("nextLocation","nextAvailableLocation","ETANext", "ETANextAvailable")]
    }  
    #
    
    #use this info to derive where they will be (on the way home, on the way to the next pickup, on the way to the dropoff)
    
    #distance to deliver
    dropOffDist = subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffDist
    dropOffTime = subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffDist/
      subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffSpeed
    
    #where will trucks be next and at what time?
    truckSched = merge(truckLocation, locationTable, by.x="nextAvailableLocation", by.y="id")
    truckSched$pickupDist = great_circle_distance(locationTable$lat[truckSched$nextAvailableLocation], locationTable$long[truckSched$nextAvailableLocation],
                                                  pickupTickets$LAT_SURF[i], pickupTickets$LONG_SURF[i]) 
    
    #also how far it is from the dropOff point back home... 
    truckSched$pickupDistBackHome = great_circle_distance(locationTable$lat[ truckSched$station], locationTable$long[truckSched$station],
                                                          pickupTickets$LAT_SURF[i], pickupTickets$LONG_SURF[i]) 
    
    #estimated times for trucks to fill the request including time to get to next location where they are available
    truckSched[["timeTillAvailable"]] = ifelse(truckSched$ETANextAvailable<=pickupTickets$pickupdate[i], ehours(0), truckSched$ETANextAvailable-pickupTickets$pickupdate[i])
    truckSched[["timetoPickupFromNextAvailable"]] = duration(truckSched$pickupDist/merge(truckSched, trucksInfo, by="truckNumber")$avgSpeed, "hours")
    truckSched[["timeUntilFilled"]] = dropOffTime+ #time it takes to drop the load off 
      truckSched$timeTillAvailable+ # timeUntilTruck is Available
      truckSched$timetoPickupFromNextAvailable #time to go from next Available point to the pickup
       
    
    ### Ignore Availability for now... just schedule an order, add in more complex scheduling later.
    # which trucks have the availability?
    # consider their availability per day * the total length of the ticket set
      
    #truckHoursSched = merge(truckHours, truckSched, by="truckNumber")
    #truckHoursSched = subset(truckHoursSched, hours< (timeUntilFilled-timeTillArrive)+hoursAvail*as.duration(difftime(max(pickupTickets$pickupdate),min(pickupTickets$pickupdate)))/ehours(1))
    
    ###
    
    #score by time to deliver and total distance (cost incurred)
    truckSched[["timeTillDeliveredRank"]] = rank(truckSched$timeUntilFilled)#, ties.method = "random")
    truckSched[["distanceTraveledRank"]] = rank(truckSched$pickupDist)
    truckSched[["distanceBackHomeRank"]] = rank(truckSched$pickupDistBackHome)
    #truckSched[["availalableRank"]] = rank(truckSched$hasHours) 
    
    
    #random assignment after that
    truckSched[["rankAdd"]]  = with(truckSched, timeTillDeliveredRank+distanceTraveledRank+distanceBackHomeRank)
    truckSched[["rankRand"]] = rank(truckSched$rankAdd, ties.method = "random")  
    
    best=which.min(truckSched$rankRand)
    pickupTickets$truckAssigned[i] = truckSched$truckNumber[best]
    pickupTickets$assignedDropOff[i] = subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOff
    pickupTickets$ETAPickup[i] = pickupTickets$pickupdate[i] + #the time the ticket came in 
      (truckSched$timeTillAvailable[best])+ #when will it be available
      (truckSched$timetoPickupFromNextAvailable[best]) #actual time to pick up the load
    pickupTickets$ETADropOff[i] = pickupTickets$ETAPickup[i]+ehours(dropOffTime)
    pickupTickets$mileageToPickup[i] = truckSched$pickupDist[best]
    pickupTickets$mileageToDropOff[i] = dropOffDist
    
  }
  pickupTickets[["type"]] = ifelse(pickupTickets$window==1,"scheduled", "forecast") 
  return(list(dispatch=pickupTickets,
              pickupDropOffPairs=pickupDropoffPairs))
}

#' A function which calculates summary metrics on the dispatch queue
#' @param dispatch a list object containing the dispatch queue
#' @return list with several data.frames containing metric summaries
#' @export
dispatchSummaries = function(dispatch, baseData){
  pickupTickets = dispatch$dispatch
  #calculate all assignments and estimated ETArrivals, ETDropOffs, BacktoHomeBase, totalHours, totalMileage, and other stats
  dispatch = pickupTickets %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsPerTruck = as.numeric(length(truckAssigned)/length(unique(truckAssigned)))
    )
  
  dispatchByField = pickupTickets %.%
    group_by(FIELD_NAME) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  dispatchByCompany = pickupTickets %.%
    group_by(COMPANY_NA) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  dispatchByCounty = pickupTickets %.%
    group_by(COUNTY) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  
  dispatchByTruck = pickupTickets %.%
    group_by(truckAssigned) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              miles = sum(mileageToPickup+mileageToDropOff),
              hours = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))),
              utilization= as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/  as.numeric(difftime(max(pickupTickets$pickupdate), min(pickupTickets$pickupdate), units="hours"))) #sum of their useful driving hours / hours available
    )
  
  pickupTicketsStations = merge(pickupTickets, baseData$trucksStations, by.x="truckAssigned", by.y="truckNumber")
  dispatchByBaseStation = pickupTicketsStations %.%
    group_by(station) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              miles = sum(mileageToPickup+mileageToDropOff),
              hours = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))),
              milesperTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursperTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsperTruck = length(truckAssigned)/length(unique(truckAssigned)),
              utilization= as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/ (as.numeric(difftime(max(ETADropOff), min(pickupdate), units="hours"))*length(unique(truckAssigned))))    
    )
  
  dispatchByDropOff = pickupTickets %.%
    group_by(assignedDropOff) %.%
    summarize(avgTimeToPickup = as.numeric(mean(difftime(ETAPickup,pickupdate,units = "hours"))),
              avgTimeToService = as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerHour = as.numeric(mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours")))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = as.numeric(length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours"))),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesperTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursperTruck = as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned))),
              loadsperTruck = length(truckAssigned)/length(unique(truckAssigned)),
              utilization= as.numeric(sum(difftime(ETADropOff,pickupdate, units="hours"))/ (as.numeric(difftime(max(ETADropOff), min(pickupdate), units="hours"))*length(unique(truckAssigned))))    
    )

  return(list(dispatch=dispatch,
               dispatchByCompany=dispatchByCompany,
               dispatchByCounty=dispatchByCounty,
               dispatchByField=dispatchByField,
               dispatchByTruck=dispatchByTruck,
               dispatchByBaseStation=dispatchByBaseStation,
               dispatchByDropOff=dispatchByDropOff))
  
}

#' A function which calculates summary metrics on the dispatch queue
#' @param dispatch a list object containing the dispatch queue
#' @return list with a handful of metric summaries
#' @export
dispatchBriefSummary = function(dispatchSummary, baseData){
  
  #for load balancing to achieve the same milesperTruck
  stationCounts = data.frame(station=names(table(baseData$trucksStations$station)), trucks=as.numeric(table(baseData$trucksStations$station)))
  sumByStation = merge(stationCounts, dispatchSummary$dispatchByBaseStation, by="station", all.x = T)[,c("miles", "trucks", "station", "loads")]
  sumByStation[is.na(sumByStation)]=0
  
  overUnder = sumByStation %.%
    arrange(desc(loads)) %.%
    mutate(milestruck = (miles/trucks)*loads,
           trucksNeeded = milestruck/sum(milestruck) *  sum(trucks),
           trucksOverUnder = trucksNeeded-trucks
    ) %.%
    arrange(desc(trucksNeeded))
  
  
  #show the overload alert
  systemOverload = mean(dispatchSummary$dispatchByBaseStation$utilization)
  
  
  
  return(list(utilizationData=with(overUnder, data.frame(BaseStation=station, loads,  trucks, loadMilesPerTruck=milestruck, trucksNeeded=round(trucksNeeded), trucksOverUnder=round(trucksOverUnder))),
              load=round(systemOverload,digits = 2),
              efficiency=round(dispatchSummary$dispatch$avgMilesperLoad, digits = 2),
              loadServiceTime=round(dispatchSummary$dispatch$avgTimeToService, digits=2)))
  
}

#' A function which takes the input data from a table in the interface and returns the new data for that table
#' @export
alterData = function(...){
  
  return(eval(substitute(alist(...)))$value)
}

dispatchRoute = function(dispatch, baseStations, trucksStations, trucksInfo, dropOffs){
  ## This function takes a set of ticket dispatches and calculates the likely route for each truck and returns a DF
  
  plyr::ddply(dispatch, .variables = "truckAssigned", function(x){
    position = data.frame(location="baseStation", lat=baseStations$lat[trucksStations$station[ x$truckAssigned[1] ]], 
                       long=baseStations$long[trucksStations$station[ x$truckAssigned[1] ]])
    for(i in 1:nrow(x)){
      position = rbind(position, data.frame(location="pickup", lat=x$LAT_SURF[i], long=x$LONG_SURF[i]))
      position = rbind(position, data.frame(location="dropOff", lat=dropOffs$lat[ x$assignedDropOff[i] ], 
                                            long=dropOffs$long[ x$assignedDropOff[i] ]))
      
      
      #if the next pickup is more than dist/speed time away then they go to the base station first
      if(i<nrow(x)){
        distPickups = great_circle_distance(x$LAT_SURF[i], x$LONG_SURF[i], x$LAT_SURF[i+1], x$LONG_SURF[i+1])
        if(x$ETAPickup[i+1]>(x$ETADropOff[i]+duration(distPickups/trucksInfo$avgSpeed[ x$truckAssigned[1] ], units = "hours")+eminutes(10))){
          
          position = rbind(position, data.frame(location="baseStation", lat=baseStations$lat[trucksStations$station[ x$truckAssigned[1] ]], 
                                                long=baseStations$long[trucksStations$station[ x$truckAssigned[1] ]]))
        }
      }else{
        position = rbind(position, data.frame(location="baseStation", lat=baseStations$lat[trucksStations$station[ x$truckAssigned[1] ]], 
                                         long=baseStations$long[trucksStations$station[ x$truckAssigned[1] ]]))
      }
    }
    return(position)
  })
  
}

#' Take the generated Base Stations and figure out where they should move to to be better placed
#' @param baseData is the list object returned from the function baseData()
#' @return data.frame with the current baseStations, their position, the recommended position and the distance between the two, and average distance reduction between it and the surrounding pickups, dropOffs and their weights
#' @export
optimizeBaseStations = function(baseData){
  
  pickupDropoffPairs = pickupDropOffs(baseData$pickups, baseData$dropOffPoints, baseData$baseStations)
  pickupDropoffPairs = merge(pickupDropoffPairs, baseData$dropOffPoints, by="dropOff")
  pickupDropoffPairs = merge(pickupDropoffPairs, baseData$pickups, by="WELL_NAME")
  
  
  points = data.frame(lat=as.numeric(c(pickupDropoffPairs$lat, pickupDropoffPairs$LAT_SURF)), long=as.numeric(c(pickupDropoffPairs$long, pickupDropoffPairs$LONG_SURF)), station=pickupDropoffPairs$station)
  
  betterLocations = kmeans(x = points[,c("lat", "long")], centers = baseData$baseStations[,c("lat", "long")])
  
  distanceFromCurrent = great_circle_distance(baseData$baseStations$lat, baseData$baseStations$long, betterLocations$centers[,"lat"], betterLocations$centers[,"long"])
  
  pickupDropoffPairs = merge(pickupDropoffPairs, baseData$baseStations, by="station")
  pickupDropoffPairs = merge(pickupDropoffPairs, data.frame(betterLocations$centers, station=c(1:nrow(baseData$baseStations))), by="station")
  
  
  impFactor = pickupDropoffPairs %.%
    group_by(WELL_NAME) %.%
    mutate(oldDist = great_circle_distance(lat.y, long.y, LAT_SURF, LONG_SURF)+ #distance base to pickup
                great_circle_distance(LAT_SURF, LONG_SURF, lat.x, long.x)+ #pickup to dropoff
                great_circle_distance(lat.x, long.x, lat.y, long.y), #dropoff back to base
              newDist = great_circle_distance(lat, long, LAT_SURF, LONG_SURF)+ #distance new base to pickup
                great_circle_distance(LAT_SURF, LONG_SURF, lat.x, long.x)+ #pickup to dropoff
                great_circle_distance(lat.x, long.x, lat, long)) %.%
    group_by(station) %.%
    arrange(station) %.%
    summarize(avgOldDist=mean(oldDist),
              avgNewDist=mean(newDist),
              medOldDist=quantile(oldDist, .5),
              medNewDist=quantile(newDist, .5),
              sdOld=sd(oldDist),
              sdNew=sd(newDist),
              improvement=-(sum(newDist)/sum(oldDist)-1)*100)
  
  
  return(list(opt=merge(data.frame(baseData$baseStations, newLat=betterLocations$centers[,"lat"], 
                          newLong=betterLocations$centers[,"long"], distanceAway=distanceFromCurrent), round(impFactor, digits=2),
                        by="station")
                          ))
}