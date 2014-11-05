great_circle_distance <- function(lat1, long1, lat2, long2) {
  lat1=lat1*pi/180
  lat2=lat2*pi/180
  long1=long1*pi/180
  long2=long2*pi/180
  
  a <- sin(0.5 * (lat2 - lat1))
  b <- sin(0.5 * (long2 - long1))
  7926 * asin(sqrt(a * a + cos(lat1) * cos(lat2) * b * b))
}

pickupOpt = function(pickupsWin, baseStations, trucksStations, trucksInfo, dropOffs){
  
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
  pickupTickets = data.frame(pickupsWin, truckAssigned=0,ETAPickup=Inf, ETADropOff=Inf, pickedUp=F, assignedDropOff=0)
  truckLocation = data.frame(trucksStations, nextLocation=0, nextAvailableLocation=0, ETANext=0, ETANextAvailable=0)
  truckHours = data.frame(trucksStations, trucksInfo, hours=0)
  locationTable = data.frame(id=1:(nrow(baseStations)+nrow(dropOffs)+nrow(pickupsWin)), 
                             type=c(rep("baseStation", nrow(baseStations)), rep("dropOff", nrow(dropOffs)),
                                    rep("pickup", nrow(pickupsWin))),
                             name=c(baseStations$station, dropOffs$dropOff, paste(pickupsWin$WELL_NAME, pickupsWin$pickupdate,sep="|")),
                             lat=c(baseStations$lat, dropOffs$lat, pickupsWin$LAT_SURF),
                             long=c(baseStations$long, dropOffs$long, pickupsWin$LONG_SURF)
  )
  
  location = merge(subset(locationTable, type=="baseStation"), trucksStations,by.x="name", by.y="station")
  truckLocation$nextAvailableLocation=merge(truckLocation, location, by="truckNumber")$id
  
  # for each ticket, assign the ticket based on closest available truck, estimate time of arrival and update truckLocation table
  # ticket assignment starts right after the first group comes in... all groups after the first are predictions
  startTime = subset(pickupTickets, window>1)$pickupdate[1]
  for(i in 1:pickupTickets){
    #update all truck's positions and ETA's in truckLocation
    
    #distance to deliver
    dropOffDist = subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffDist
    dropOffTime = subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffDist/
      subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$dropOffSpeed
    
    
    #trucksAvail = subset(trucksStations, station==subset(pickupDropoffPairs, WELL_NAME==pickupTickets$WELL_NAME[i])$station)
    
    #which trucks are available at this time? Assume all for now
    
    #where will trucks be next and at what time?
    truckSched = merge(truckLocation, locationTable, by.x="nextAvailableLocation", by.y="id")
    truckSched$pickupDist = great_circle_distance(locationTable$lat[truckSched$nextAvailableLocation], locationTable$long[truckSched$nextAvailableLocation],
                                                  pickupTickets$LAT_SURF[i], pickupTickets$LONG_SURF[i]) 
    
    #also how far it is from the dropOff point back home... 
    truckSched$pickupDistBackHome = great_circle_distance(locationTable$lat[ truckSched$station], locationTable$long[truckSched$station],
                                                          pickupTickets$LAT_SURF[i], pickupTickets$LONG_SURF[i]) 
    
    #estimated times for trucks to fill the request including time to get to next location where they are available
    truckSched[["timeTillAvailable"]] = ifelse(truckSched$ETANextAvailable==0, 0, (ymd_hms(truckSched$ETANextAvailable)-startTime)/ehours(1))
    truckSched[["timetoPickupFromNextAvailable"]] = truckSched$pickupDist/merge(truckSched, trucksInfo, by="truckNumber")$avgSpeed
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
    pickupTickets$ETAPickup = startTime+ #the time now
      truckSched$timeTillAvailable[best]+ #when will it be available
      truckSched$timetoPickupFromNextAvailable[best] #actual time to pick up the load
    pickupTickets$ETADropOff = pickupTickets$ETAPickup[i]+dropOffTime
    
    #calculate all assignments and estimated ETArrivals, ETDropOffs, BacktoHomeBase, totalHours, totalMileage, and other stats
    
  }
                             
  #now do some population based optimization of schedule (or other max flow type algorithms)
  
  
  
  
}