library(dplyr)
library(glue)
library(terra)
library(tidygeocoder)
library(readnoaa)
library(rhdf5)
library(sf)
library(tigris)
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

#Initialize date ranges vector so that we can name our list of dataframes 
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

#uuse NOAMRMS data from AWS
# found aws datasets at mesonet.agron.iastate.edu/mrms
#link to s3 data https://registry.opendata.aws/noaa-mrms-pds/
# More info at : https://blog.djnavarro.net/posts/2022-03-17_using-aws-s3-in-r/
#from browsing bucket I found CONUS folders : https://noaa-mrms-pds.s3.amazonaws.com/index.html#CONUS/PrecipRate_00.00/
#used file structure found after coding to loop over date ranges
library(aws.s3)

NOAMRMMS_bucket<-"noaa-mrms-pds/"
region<-"us-east-1"
bucket_info<-bucket_exists(bucket=NOAMRMMS_bucket,region=region)
bucket_check<-bucket_info[1]

state_bounds<-states(cb=FALSE,class='sf')
sort(unique(state_bounds$NAME))
#found DC's name as District of Columbia
dc_bounds<-state_bounds%>%
  filter(NAME=='District of Columbia')
dc_vect<-vect(dc_bounds)

#pull populated dc raster to create an "empty template" for files that cannot be pulled
#Earliest gridded precipitation data is 20201014 so I will set dates before 20201014 as NA 

empty_rast<-function(){
  rateGZname<-glue('/vsigzip//vsicurl/https://noaa-mrms-pds.s3.amazonaws.com/CONUS/PrecipRate_00.00/20201014/MRMS_PrecipRate_00.00_20201014-000000.grib2.gz')
  rstDay<-rast(rateGZname)
  state_bounds<-states(cb=FALSE,class='sf')
  #found DC's name as District of Columbia
  dc_bounds<-state_bounds%>%
    filter(NAME=='District of Columbia')
  dc_vect<-vect(dc_bounds)
  
  dc_vect_project<-terra::project(dc_vect,crs(rstDay))
  dcSFdailyDat<-terra::crop(rstDay,dc_vect_project)
  maskedDCDaily<-terra::mask(dcSFdailyDat,dc_vect_project)
  empt_<-terra::init(maskedDCDaily,NA)
  return(rast(empt_))
}

formatDT_NOAA<-function(dtRange){
  #date range has to be in cormat YYYY-mm-dd HH:MM - YYYY-mm-dd HH:MM 
  formatted<-as.character(
    seq(
      from = lubridate::ymd_hm(substr(dtRange[1],1,16)),
      to = lubridate::ymd_hm(substr(dtRange[1],20,35)), 
      by = "hour")
    )
  return(formatted)
}

empty_raster_DC<-empty_rast()



if(bucket_check){
  feelme<-lapply(date_ranges[1],function(x){
    eachHour<-formatDT_NOAA(x)
    #put each datetime in date format that is shown  in CONUS/PrecipRate folder 
    #remove all none digit using regex replacement
    #tried downloading to temp file created in R but was having issues with that. Decided to stream into R instead using terra package
    # add /vsigzip//vsicurl/ to properly be able to get rast object from URL
    # https://gdal.org/en/stable/user/virtual_file_systems.html
    onlyDigits<-gsub("[^0-9]","",eachHour)
    dt_timeRST<-base::mapply(FUN=function(dtForm,digForm){
      print(as.numeric(digForm))
      if(base::all(as.numeric(digForm)<20201014000000)){
        message("Data prior to 20201014. Adding Empty raster")
        temprst<-empty_raster_DC
        time(temprst)<-as.POSIXct(dtForm,tz='UTC')
        return(temprst)
      }else{
        ymd_d<-substr(digForm,1,8)
        formatDT<-glue("{substr(digForm,1,8)}-{substr(digForm,9,15)}")
        preciprate_suffix<-glue('{formatDT}/MRMS_PrecipRate_00.00_')
        rateGZname<-glue('/vsigzip//vsicurl/https://noaa-mrms-pds.s3.amazonaws.com/CONUS/PrecipRate_00.00/{ymd_d}/{preciprate_suffix}.grib2.gz')
        
        rstDay<-terra::rast(rateGZname)
        #project,crop and mask onto DC high resolution raster 
        dc_vect_project<-terra::project(dc_vect,crs(rstDay))
        dcSFdailyDat<-terra::crop(rstDay,dc_vect_project)
        maskedDCDaily<-terra::mask(dcSFdailyDat,dc_vect)
        terra::time(maskedDCDaily)<-as.POSIXct(dtForm,tz='UTC')
        return(maskedDCDaily)
      }
      
    },eachHour,onlyDigits,SIMPLIFY=FALSE)
    return(terra::rast(dt_timeRST))
    }
  )
  
}

apply(dcFlood_times,1,function(x){
  
  startDate<-substr(x[['begin_date']],1,10)
  endDate<-substr(x[['end_date']],1,10)
  get_prism_dailys(minDate = startDate,
                   maxDate = endDate,
                   keepZip = FALSE,
                   type = 'ppt')
  
  
})

#rast test
testrast<-rast("data/prismtmp/prism_ppt_us_25m_19960618/prism_ppt_us_25m_19960618.bil")
#pulled most detailed TIGER/line file
state_bounds<-states(cb=FALSE,class='sf')
sort(unique(state_bounds$NAME))

#found DC's name as District of Columbia
dc_bounds<-state_bounds%>%
  filter(NAME=='District of Columbia')

#turn into raster
dc_vect<-vect(dc_bounds)
dc_vect<-project(dc_vect,crs(testrast))

dcSFdailyDat<-crop(testrast,dc_vect)
maskedDCDaily<-terra::mask(dcSFdailyDat,dc_vect)
#how to download rhdf5
#install.packages("BiocManager")
#BiocManager::install('rhdf5')