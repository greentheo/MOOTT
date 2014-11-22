great_circle_distance <- function(lat1, long1, lat2, long2) {
  lat1=lat1*pi/180
  lat2=lat2*pi/180
  long1=long1*pi/180
  long2=long2*pi/180
  
  a <- sin(0.5 * (lat2 - lat1))
  b <- sin(0.5 * (long2 - long1))
  7926 * asin(sqrt(a * a + cos(lat1) * cos(lat2) * b * b))
}

pickupOpt = function(pickupsWin, baseStations, trucksStations, trucksInfo, dropOffs,...,truckLocation=NULL){
  
#   withProgress(message = 'Dispatch Optimization in progress',
#                detail = 'Creating DispatchSchedule...', value = 0, {
#                  incProgress(.01)
                 
  pickupsWin=pickupsWin %.%
    mutate(day = format(ymd_hms(pickupdate), "%d")) %.%
    arrange(pickupdate)
  
  pickupDropoffPairs = pickupsWin %.%
    group_by(WELL_NAME) %.%
    summarize(dropOff=dropOffs[which.min(great_circle_distance(LAT_SURF, LONG_SURF, dropOffs$lat, dropOffs$long)), "dropOff"],
              dropOffDist=min(great_circle_distance(LAT_SURF[1], LONG_SURF[1], dropOffs$lat, dropOffs$long)),
              dropOffSpeed=rnorm(1, 30, 5),
              station=baseStations[which.min(great_circle_distance(LAT_SURF, LONG_SURF, baseStations$lat, baseStations$long)), "station"],
              stationDist=min(great_circle_distance(LAT_SURF[1], LONG_SURF[1], baseStations$lat, baseStations$long))
              )
  
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
      
      truckLastLocation = ddply(truckLast, .(truckAssigned), function(x){
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
    
    #print(pickupTickets[i,])
  }
   
  #calculate all assignments and estimated ETArrivals, ETDropOffs, BacktoHomeBase, totalHours, totalMileage, and other stats
  dispatch = pickupTickets %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  dispatchByField = pickupTickets %.%
    group_by(FIELD_NAME) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  dispatchByCompany = pickupTickets %.%
    group_by(COMPANY_NA) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  dispatchByCounty = pickupTickets %.%
    group_by(COUNTY) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesPerTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursPerTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsPerTruck = length(truckAssigned)/length(unique(truckAssigned))
    )
  
  
  dispatchByTruck = pickupTickets %.%
    group_by(truckAssigned) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              miles = sum(mileageToPickup+mileageToDropOff),
              hours = sum(difftime(ETADropOff,pickupdate, units="hours")),
              utilization= sum(difftime(ETADropOff,pickupdate, units="hours"))/  as.numeric(difftime(max(pickupTickets$pickupdate), min(pickupTickets$pickupdate), units="hours")) #sum of their useful driving hours / hours available
    )
  
  pickupTicketsStations = merge(pickupTickets, trucksStations, by.x="truckAssigned", by.y="truckNumber")
  dispatchByBaseStation = pickupTicketsStations %.%
    group_by(station) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              miles = sum(mileageToPickup+mileageToDropOff),
              hours = sum(difftime(ETADropOff,pickupdate, units="hours")),
              milesperTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursperTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsperTruck = length(truckAssigned)/length(unique(truckAssigned)),
              utilization= sum(difftime(ETADropOff,pickupdate, units="hours"))/ (as.numeric(difftime(max(ETADropOff), min(pickupdate), units="hours"))*length(unique(truckAssigned)))    
    )
  
  dispatchByDropOff = pickupTickets %.%
    group_by(assignedDropOff) %.%
    summarize(avgTimeToPickup = mean(difftime(ETAPickup,pickupdate,units = "hours")),
              avgTimeToService = mean(difftime(ETADropOff,pickupdate, units="hours")),
              profitPerHour = mean(GrossProfit*200)/as.numeric(mean(difftime(ETADropOff,pickupdate, units="hours"))),
              profitPerLoad = mean(GrossProfit*200),
              loadsPerHour = length(GrossProfit)/as.numeric(difftime(max(pickupdate), min(pickupdate), units="hours")),
              loads = length(GrossProfit),
              avgMilesToPickup = mean(mileageToPickup),
              avgMilesperLoad = mean(mileageToPickup+mileageToDropOff),
              profitPerMile = mean(GrossProfit*200)/mean(mileageToPickup+mileageToDropOff),
              milesperTruck = sum(mileageToPickup+mileageToDropOff)/length(unique(truckAssigned)),
              hoursperTruck = sum(difftime(ETADropOff,pickupdate, units="hours"))/length(unique(truckAssigned)),
              loadsperTruck = length(truckAssigned)/length(unique(truckAssigned)),
              utilization= sum(difftime(ETADropOff,pickupdate, units="hours"))/ (as.numeric(difftime(max(ETADropOff), min(pickupdate), units="hours"))*length(unique(truckAssigned)))    
    )
#   incProgress(.25)
  #}) #end of with progress
  return(list(dispatch=pickupTickets,
              dispatchSummary=list(dispatch=dispatch,
                                   dispatchByCompany=dispatchByCompany,
                                   dispatchByCounty=dispatchByCounty,
                                   dispatchByField=dispatchByField,
                                   dispatchByTruck=dispatchByTruck,
                                   dispatchByBaseStation=dispatchByBaseStation,
                                   dispatchByDropOff=dispatchByDropOff)))
}

dispatchRoute = function(dispatch, baseStations, trucksStations, trucksInfo, dropOffs){
  ## This function takes a set of ticket dispatches and calculates the likely route for each truck and returns a DF
  
  ddply(dispatch, .(truckAssigned), function(x){
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