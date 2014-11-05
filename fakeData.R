## this script takes existing well data and makes some fake data for use in the demo

library(dplyr)
library(lubridate)
library(MASS)

#Utah Data
OG = read.csv('data/UT_OilGas.csv')
OG = subset(OG, format( mdy(MODIFY_DAT), "%Y")=="2014" & CUM_OIL>0 )

#model the pickup frequency of wells by size
# cots = readRDS('data/basicCOTSData.rds')
# cotsD = cots %.%
#   filter(n()>1000) %.%
#   group_by(LSE_LEASE_NAME) %.% 
#   arrange(ymd_hms(TCK_DOT_TURNEDON_DATE)) %.% 
#   mutate(daysSinceLast=c(NA,(diff(ymd_hms(TCK_DOT_TURNEDON_DATE))/edays(1)))) %.%
#   filter(mean(daysSinceLast, na.rm=T)>0) %.%
#   summarize(distMean=mean(daysSinceLast,na.rm = T),
#             pValueExp=ks.test(as.numeric(na.omit(daysSinceLast)), "pexp", 1/distMean)$p.value) %.%
#   mutate(sig = ifelse(pValueExp>.05, '*', ''))


## well pickup times are exponentially distributed, therefore we can apply a simple rule for well pickup times

# well volume / tank size = number of pickups per year (poisson), which translates into per/day
# simulate with the pickup rate for exponential pickup times.

OG[["OilRate"]] = OG$CUM_OIL/200/((mdy(OG$MODIFY_DAT)-mdy(OG$ORIG_COMPL))/edays(1))  
OG[["WaterRate"]] = OG$CUM_H2O/200/((mdy(OG$MODIFY_DAT)-mdy(OG$ORIG_COMPL))/edays(1))  
OG[["GrossProfit"]] = runif(nrow(OG))
saveRDS(na.omit(subset(OG, OilRate>0)), file = 'data/UT_OilGaswRates.rds')







