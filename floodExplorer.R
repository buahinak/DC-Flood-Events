library(dplyr)
library(glue)
library(terra)
library(tidygeocoder)
library(readnoaa)
library(rhdf5)
library(sf)
library(tigris)
library(aws.s3)
library(ggplot2)
library(tidyterra)

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

#looked at 25 nearby stations to Foggy Bottom,DC. 
dc_stations<-noaa_nearby(lat=38.9007,lon=-77.0503)%>%
  select(station,name)

#checked how robust data from 25 stations were
robustnessCheck<-apply(dc_stations,1,function(x){
  coverage<-noaa_coverage(x['station'])%>%filter(element=='PRCP')%>%mutate(name=x['name'])
  return(coverage)
})%>%bind_rows()

#Create md tale for Read me 
#knitr::kable(robustnessCheck,format='markdown')


#Washington Reagen had the most coverage of precipitation based on our flood events so we will pull 
# data from Washington reagan station

#Pull station ID
dc_reagan<-noaa_nearby(lat=38.9007,lon=-77.0503)%>%
  filter(name=='WASHINGTON REAGAN NATL AP')%>%
  pull(station)

#ISD number for Washington Reagan had to be used for global hourly dataset 72405013743
#Pull all hourly data in one call then filter by flood time date ranges to save time

#function to pull noaa data by station and cleans the data
pull_dateRanges<-function(floodDT){
  date_ranges<-glue_data(floodDT,"{begin_date} {begin_time} - {end_date} {end_time}")
  return(date_ranges)
}

pull_HourlyPRCP_st<-function(station_isd="72405013743",
                             mindt,
                             maxdt,
                             prcpDat=c('AA1','AA2','AA3','AA4')){
  
  
  dca<-noaa_get(dataset = "global-hourly",
                station=station_isd,
                start_date = mindt,
                end_date = maxdt,
                datatypes = prcpDat,
                include_location = TRUE)

  return(dca)
}

PRCP_stat<-function(station_isd="72405013743",
                    floodDt,
                    prcpDat=c('AA1','AA2','AA3','AA4')){
  
  earliestDate<-min(as.Date(dcFlood_times$begin_date))
  latestDate<-max(as.Date(dcFlood_times$begin_date))
  
  currData<-pull_HourlyPRCP_st(mindt=earliestDate,maxdt=latestDate)
  
  print(summary(currData))
  precipData<-apply(floodDt,1,function(x){
    selMinDt<-x[['begin_date']]
    selMinTime<-x[['begin_time']]
    selMaxDt<-x[['end_date']]
    selMaxTime<-x[['end_time']]
    
    startTime<-lubridate::ymd_hm(glue("{selMinDt} {selMinTime}"))
    endTime<-lubridate::ymd_hm(glue("{selMaxDt} {selMaxTime}"))
    
    currData<-currData%>%
      filter(date>=startTime & 
               date<=endTime)
    message(glue("Pulling data for {startTime} - {endTime}"))
    
    #go through each date range and filter out the flood dates we are concerned with 

    return(currData)
  })%>%bind_rows()
  
  #clean columns
  for(p in tolower(prcpDat)){
    #add number to names 
    wider_cols<-c("period_q","depth_dim","cond_code","qual_code")
    wider_cols<-glue('{wider_cols}_{substr(p,3,3)}')
    
    #convert depth dimension to mm 
    precipData<-precipData%>%
      tidyr::separate(col=all_of(p),into = wider_cols,sep=",",fill='right',convert=TRUE)%>%
      mutate(across(starts_with("depth_dim"), ~ if_else(.==9999,NA,./10)),
             across(starts_with("period_q"), ~ if_else(.==99,NA,.)),
      )
  }
  return(precipData)
}


PRCPdataOBJ<-PRCP_stat(floodDt=dcFlood_times)
date_ranges<-pull_dateRanges(dcFlood_times)
#Initialize date ranges vector so that we can name our list of dataframes 

#function that intakes a hourly PRCP and keeps data in flood event date range 
#This will also create a global vector with all the date ranges we are concerned with 
#This will help when pulling gridded precipitation data

#uuse NOAMRMS data from AWS
# found aws datasets at mesonet.agron.iastate.edu/mrms
#link to s3 data https://registry.opendata.aws/noaa-mrms-pds/
# More info at : https://blog.djnavarro.net/posts/2022-03-17_using-aws-s3-in-r/
#from browsing bucket I found CONUS folders : https://noaa-mrms-pds.s3.amazonaws.com/index.html#CONUS/PrecipRate_00.00/
#used file structure found after coding to loop over date ranges


state_bounds<-states(cb=FALSE,class='sf')
sort(unique(state_bounds$NAME))
#found DC's name as District of Columbia
dc_bounds<-state_bounds%>%
  filter(NAME=='District of Columbia')
dc_vect<-vect(dc_bounds)
#create master dc_sample
dc_sampling <- terra::rast(terra::ext(dc_vect), resolution = 0.01, crs = terra::crs(dc_vect))
#pull populated dc raster to create an "empty template" for files that cannot be pulled
#Earliest gridded precipitation data is 20201014 so I will set dates before 20201014 as NA 


formatDT_NOAA<-function(dtRange){
  #date range has to be in cormat YYYY-mm-dd HH:MM - YYYY-mm-dd HH:MM 
  dtformStart<-lubridate::ymd_hm(substr(dtRange,1,16))
  dtformEnd<-lubridate::ymd_hm(substr(dtRange,20,35))
  formatted<-as.character(
    seq(
      from = lubridate::floor_date(dtformStart,unit='hour'),
      to = lubridate::ceiling_date(dtformEnd,unit='hour'), 
      by = "hour")
    )
  #filter out odd minutes of day because S3 bucket only has data per 2 minutes
  #evens<-formatted[lubridate::minute(formatted) %% 2 ==0 |lubridate::minute(formatted)==0]
  
  # if date range is shorter than 2 mins and isnt an even minute,evens is empty. 
  #if evens is empty we will return the date from the dcFloodtimes 
  #if(length(evens)==0){
    #return(formatted)
 # }
  return(formatted)
}

conf_buck<-function(bucket_arn,region){
  bucket_info<-bucket_exists(bucket=NOAMRMMS_bucket,region=region)
  bucket_check<-bucket_info[1]
  return(bucket_check)
}
NOAMRMMS_bucket<-"s3://noaa-mrms-pds/"
region<-"us-east-1"

bucket_check<-conf_buck(NOAMRMMS_bucket,region)

# going
then<-Sys.time()

#pulls gridded rast data from NOAAA MRMS for a datetime 
#put each datetime in date format that is shown  in CONUS/PrecipRate folder 
#remove all none digit using regex replacement
#tried downloading to temp file created in R but was having issues with that. Decided to stream into R instead using terra package
# add /vsigzip//vsicurl/ to properly be able to get rast object from URL
# https://gdal.org/en/stable/user/virtual_file_systems.html
getGriddedPRCP<-function(dt,
                         MRMSFOLDER="MultiSensor_QPE_01H_Pass2_00.00",
                         arn='https://noaa-mrms-pds.s3.amazonaws.com',
                         rastProject,
                         sampleRast){
  
  onlyDigits<-gsub("[^0-9]","",dt)
  ymd_d<-substr(onlyDigits,1,8)
  formatDT<-glue("{substr(onlyDigits,1,8)}-{substr(onlyDigits,9,15)}")
  fileName<-glue("MRMS_{MRMSFOLDER}_{formatDT}.grib2.gz")
  gzPath<-glue("/vsigzip//vsicurl/{arn}/CONUS/{MRMSFOLDER}/{ymd_d}/{fileName}")
  rstDay<-terra::rast(gzPath)
  #project,crop and mask onto DC high resolution raster 
  vect_project<-terra::project(rastProject,crs(rstDay))
  prcp<-terra::crop(rstDay,vect_project)
  masked_prcp<-terra::mask(prcp,vect_project)
  align_prcp <- terra::resample(masked_prcp, sampleRast, method = "near")
  #terra::ext(align_prcp) <- terra::ext(sampleRast)
  terra::time(align_prcp)<-as.POSIXct(dt,tz='UTC')
  return(align_prcp)
}

#pass vector of date ranges in 'YYYY-MM-DD HH:MM - YYYY-MM-DD HH:MM' format along with check on bucket
#availability into function to compile NOAA MRMS 

compilePRCP<-function(date_range,bucket_available){
  if(bucket_check){
    #missing_rast<-terra::init(dc_sampling,NA)
    #alighn_missing <- terra::resample(missing_rast, dc_sampling, method = "near")
    listed_rasters<-lapply(date_range,function(x){
      eachHour<-formatDT_NOAA(x)

      dt_timeRST<-lapply(eachHour,function(dt){
        
        #error catch. If no folder for date, return NA and move to next date Range
        rastfin<-tryCatch({
          maskedDCDaily<-getGriddedPRCP(dt,rastProject = dc_vect,sampleRast=dc_sampling)
          message(glue("Pulled event from {dt}"))
          maskedDCDaily
        },error=function(e){
          message(glue("Event missing for {dt}\n{e$message}"))
          # misErr<-missing_rast
          # terra::time(misErr)<-as.POSIXct(dt,tz='UTC')
          # names(misErr) <- "MultiSensor_QPE_01H_Pass2_0-GPML"
          # misErr
          return(NULL)
        })
        return(rastfin)
        
      })
      filtered_inside <- Filter(Negate(is.null), dt_timeRST)
      
      if (length(filtered_inside) > 0) {
        return(terra::rast(filtered_inside))
      } else {
        return(NULL) # Pass the skip up the chain
      }
    })
    
    filtered_outside<-Filter(Negate(is.null), listed_rasters)
    compiledRasters<-terra::rast(filtered_outside)
  }else{
    message("Bucket isn't available")
  }
}

#pull date ranges from dcFlood_times
date_ranges<-pull_dateRanges(dcFlood_times)

#compile PRCP from rasters
# Starting from flood event 99 since MRMS's earliest data is from 20201014/
#for project puprosee, will only run on one flood event
sampleDCFloodevents<-date_ranges[100]
dcFloodPRCP<-compilePRCP(sampleDCFloodevents,conf_buck(NOAMRMMS_bucket,region))


#Create RHDF5 file

h5_file <- "data/dc_floodEvent_DB.h5"
if(file.exists(h5_file)) {
  file.remove(h5_file)
  h5closeAll()
  }
h5createFile(h5_file)



# split into time series group and gridded precipitation group
# allows for possible extension to other gridded precipitation sources like PRISm
# also allows for other stations to be added to station time series group
h5createGroup(h5_file, "station_TimeSeries")
h5createGroup(h5_file, "station_TimeSeries/Washington National")
h5createGroup(h5_file, "gridded_precipitation")
h5createGroup(h5_file, "gridded_precipitation/NOAAA MRMS")

#write station data
PRCPdataOBJ$date_char <- as.character(PRCPdataOBJ$date) 
h5write(PRCPdataOBJ, h5_file, "station_TimeSeries/Washington National/ts_data")


#write gridded precipitation data
dcFloodPRCPArr <- terra::as.array(dcFloodPRCP)
h5write(dcFloodPRCPArr, h5_file, "gridded_precipitation/NOAAA MRMS/QPE_01HOURS_data")
dc_reagan<-noaa_nearby(lat=38.9007,lon=-77.0503)%>%
  filter(name=='WASHINGTON REAGAN NATL AP')

station<-as.character(dc_reagan%>%pull(station))
lat<-as.character(dc_reagan%>%pull(latitude))
long<-as.character(dc_reagan%>%pull(longitude))

#add metadata and attriutes for time series data
pointr <- H5Fopen(h5_file)
actual<- H5Dopen(pointr,"station_TimeSeries/Washington National/ts_data")
h5writeAttribute(station, actual, "Station ID")
h5writeAttribute(glue("{lat},{long}"),actual, "Coordinates")
h5writeAttribute("mm", actual, "Units")
h5writeAttribute("HOURLY ACCUMULATION OF LIQUID PRECIPITATION. SOME EVENTS HAVE >AN HOUR ", actual, "Precipitation Collection")


#add metadata and attributes for gridded precipitation data
actual<- H5Dopen(pointr,"gridded_precipitation/NOAAA MRMS/QPE_01HOURS_data")
crsObj <- terra::crs(dcFloodPRCP)
minMxVec <- as.vector(terra::ext(dcFloodPRCP)) 
timeIND <- as.character(terra::time(dcFloodPRCP)) 

h5writeAttribute(crsObj, actual, "CRS")
h5writeAttribute(minMxVec, actual, "Extent Bound Box")
h5writeAttribute(timeIND, actual, "Time Index(UTC)")
h5writeAttribute("mm", actual, "Units")
h5writeAttribute("HOURLY ACCUMULATION OF LIQUIDPRECIPITATION", actual, "Precipitation Collection")

H5Fclose(pointr)
H5Dclose(actual)
h5closeAll()

#get metadata summary for documentation
rhdf5::h5ls(h5_file)

station_meta <- rhdf5::h5readAttributes(h5_file, "station_TimeSeries/Washington National/ts_data")

meta_df <- data.frame(
  Attribute = names(gridded_meta),
  Value = sapply(gridded_meta, function(x) paste(x, collapse = ", ")),
  row.names = NULL
)
knitr::kable(meta_df, format = "markdown", col.names = c("Metadata Attribute", "Value / Description"))



#how to download rhdf5
#install.packages("BiocManager")
#BiocManager::install('rhdf5')

#dates must be in ymd format
hdf5_stationQuery<- function(hdf5_p, start_time, end_time) {
  
  dt_p <- "station_TimeSeries/Washington National/ts_data"
  station_data <- rhdf5::h5read(hdf5_p, dt_p)
  station_data$date <- lubridate::ymd_hms(station_data$date_char, tz = "UTC")
  
  dt_start <- lubridate::ymd(start_time, tz = "UTC")
  dt_end <- lubridate::ymd(end_time, tz = "UTC")
  event_ts <- station_data %>%
  dplyr::filter(date >= dt_start & date <= dt_end)
  
  return(event_ts)
}

#pull station data from 2020-10 to 2023-05
ts_station_data <- hdf5_stationQuery(h5_file, "1980-10-12", "2026-05-20")
print(head(event_data))

#data range has to be created using pull_dateRanges(). Pass the flood event dataset as a parameter into this function 
# function only works on one date range at a time currently
hdf5_griddedQuery<- function(hdf5_p, date_range) {
  doi<-formatDT_NOAA(date_range)
  dt_start<-min(lubridate::ymd_hms(doi,tz="UTC"))
  dt_end<-max(lubridate::ymd_hms(doi,tz="UTC"))
  
  dt_p <- "gridded_precipitation/NOAAA MRMS/QPE_01HOURS_data"
  meta <- rhdf5::h5readAttributes(hdf5_p, dt_p)
  times_grid <- as.POSIXct(meta$`Time Index(UTC)`, tz = "UTC")
  
  
  #find matrix values that are within dates
  indInFrame <- tibble(date = times_grid) %>%
    mutate(rownum = row_number()) %>%
    filter(date >= dt_start & date <= dt_end) %>%
    pull(rownum)
  filteredDat <- rhdf5::h5read(hdf5_p, dt_p, index = list(NULL, NULL, indInFrame),drop = FALSE)
  filteredRast <- terra::rast(filteredDat)
  
  terra::ext(filteredRast) <- as.numeric(meta$`Extent Bound Box`)
  terra::crs(filteredRast) <- meta$CRS
  terra::time(filteredRast) <- times_grid[indInFrame]
  names(filteredRast) <- rep("MultiSensor_QPE_01H_Pass2_0-GPML", length(indInFrame))

  return(filteredRast)
}

#example of available data range that can be pulled for
date_ranges<-'1996-01-01 00:00 - 2026-01-01 00:00'

#pull example date range from flood event and  pass items from that 
gridded_data <- hdf5_griddedQuery(h5_file, date_ranges)
print(gridded_data)


plot_station_ts <- function(event_ts) {
  p <- ggplot(event_ts, aes(x = date, y = depth_dim_1)) +
    geom_col(fill = "dodgerblue4", color = "black", width = 3600) + # Width in seconds (1 hr)
    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
    labs(
      title = "NOAA Station Precipitation Washington National Reagan",
      subtitle = glue::glue("Event Window: {min(event_ts$date)} to {max(event_ts$date)}"),
      x = "Time (UTC)",
      y = "Precipitation (mm)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
  
  return(p)
}

#date Range is passed to title the figure
plot_event_raster <- function(event_raster,dateRange,vect) {
  
  # Aggregate hourly data over space of date range
  event_total <- terra::app(event_raster, fun = "sum", na.rm = TRUE)
  names(event_total) <- "Total_Precipitation_mm"
  
  p <- ggplot() +
    geom_spatraster(data = event_total) +
    scale_fill_viridis_c(
      option = "mako", 
      direction = -1, 
      na.value = "transparent",
      name = "Total\nPrecip (mm)"
    ) +
    labs(
      title = glue("DC Area Accumulated: {dateRange} "),
      subtitle = glue::glue("Aggregated {terra::nlyr(event_raster)} hourly spatial layers")
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
  #draw DC CRS vector over plot
  if (!is.null(dc_vect)) {
    p <- p + geom_spatvector(data = dc_vect, fill = NA, color = "red", linewidth = 1)
  }
  
  return(p)
}


station_plot <- plot_station_ts(ts_station_data)
print(station_plot)

radar_plot <- plot_event_raster(gridded_data, dateRange="2020-11-12 04:00 - 2025-07-19 19:00",vect=dc_vect)
print(radar_plot)
