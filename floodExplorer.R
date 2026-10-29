library(dplyr)
library(glue)
library(jsonlite)
library(httr)
library(prism)
library(readnoaa)
dcFlood_times<-read.csv("data/DC_flood_times.csv")

#check missing

dcFlood_times%>%
  filter(if_any(everything(),is.na))

earliestDate<-min(as.Date(dcFlood_times$begin_date))
latestDate<-max(as.Date(dcFlood_times$begin_date))

print(glue("Earliest Date to pull environmental data from: {earliestDate} "))
print(glue("Latest Date to pull environmental data from: {latestDate} "))

#find distinct years of data needed to pull
startyrs<-unique(substr(dcFlood_times$begin_date,1,4))
endyrs<-unique(substr(dcFlood_times$end_date,1,4))
yrsCaptured<-unique(c(startyrs,endyrs))

#Washington Reagen has most up to date weather data 
dc<-noaa_nearby(lat=38.9007,lon=-77.0503)%>%
  filter(name=='WASHINGTON REAGAN NATL AP')%>%
  pull(station)

#ISD number had to be used for global hourly dataset 72405013743
#Pull all hourly data in one call then filter by flood time date ranges to save time

dca<-noaa_get(dataset = "global-hourly",
              station='72405013743',
              start_date = earliestDate,
              end_date = latestDate,
              datatypes = c('AA1','AA2','AA3','AA4'),
              include_location = TRUE)

date_ranges<-c()
dcaFiltered<-apply(dcFlood_times,1,function(x){
  startTime<-glue("{x['begin_date']} {x['begin_time']}")
  endTime<-glue("{x['end_date']} {x['end_time']}")
  
  #go through each date range and filter out the flood dates we are concerned with 
  filtDat<-dca%>%
    filter(lubridate::ymd_hms(date)>=lubridate::ymd_hm(startTime)
           & lubridate::ymd_hms(date)<=lubridate::ymd_hm(endTime))
  message(glue("Pulling data for {startTime} - {endTime}"))
  
  date_ranges<<-c(date_ranges,glue("{startTime} - {endTime}"))
  return(filtDat)
})

#create names for nested dataframe list created in dcaFiltered
names(dcaFiltered)<-date_ranges
