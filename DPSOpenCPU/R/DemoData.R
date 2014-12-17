## Function to generate Demo Data 


#' Generate Base Demo Data
#' @import dplyr lubridate
#' @param pickups is the number of pickups to select from the data set
#' @return data.frame with the wells, pickups and etc.
#' @export

baseData = function(pickups=1000, numTrucks=100, numStations=10, numDropOffs=30){
#   OG = readRDS('../data//UT_OilGaswRates.rds')
  data(UT_OilGaswRates)
  OGSample = sample(1:nrow(OG), pickups)
  OGsub = OG[OGSample,]#input$numLeases),]
  
  #last hour of tickets + 3 days of forecast generation
  wells = data.frame(WELL_NAME=rep(OGsub$WELL_NAME, 15), misc=1)
  OGsub = merge(wells, OGsub, by = "WELL_NAME",all.x = T)
  OGsub = OGsub %.%
    group_by(WELL_NAME) %.%
    mutate(pickups=cumsum(rexp(15, OilRate))) %.%
    filter(pickups<=3) %.%
    mutate(pickupdate=ymd_hms(format(as.POSIXct(Sys.time()), "%Y-%m-%d %H:%M:%S"))+edays(pickups)-ehours(1))
  
  values = list()
  values[["OGsub"]] = OGsub
  
  values[["baseStations"]] = data.frame(station=1:round(numTrucks/numStations), 
                                   lat=rnorm(round(numTrucks/numStations), mean(OGsub$LAT_SURF), sd(OGsub$LAT_SURF)), 
                                   long=rnorm(round(numTrucks/numStations),  mean(OGsub$LONG_SURF), sd(OGsub$LONG_SURF)))
  
  dropOffs = sample(1:nrow(values$baseStations), numDropOffs, replace=T)
  values[["dropOffPoints"]] = data.frame(dropOff=1:numDropOffs, 
                                    lat=rnorm(numDropOffs, 0, .5)+values$baseStations[dropOffs, "lat"],
                                    long=rnorm(numDropOffs, 0, .5)+values$baseStations[dropOffs, "long"]
  )
  
  values[["trucksStations"]] = data.frame(truckNumber=1:numTrucks, station=sample(1:numStations, numTrucks, replace = T))  
  values[["trucksInfo"]] = data.frame(truckNumber=1:numTrucks, hoursAvail=12, avgSpeed=30, available=T)
  
  values[["pickups"]] = pickups = OG[OGSample, ]
  
  return(values)
}

