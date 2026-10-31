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

#pull date ranges from flood event data csv file
pull_dateRanges<-function(floodDT){
  date_ranges<-glue_data(floodDT,"{begin_date} {begin_time} - {end_date} {end_time}")
  return(date_ranges)
}

#function to pull NOAA data by station and cleans the data
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

#pull precipiation time series data from reagan station
#function that intakes a hourly PRCP and keeps data in flood event date range 
PRCP_stat<-function(station_isd="72405013743",
                    floodDt,
                    prcpDat=c('AA1','AA2','AA3','AA4')){
  
  earliestDate<-min(as.Date(dcFlood_times$begin_date))
  latestDate<-max(as.Date(dcFlood_times$begin_date))
  
  #pull data
  currData<-pull_HourlyPRCP_st(mindt=earliestDate,maxdt=latestDate)
  
  #filter out data based on dates in flood event csv
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
  
    return(currData)
  })%>%bind_rows()
  
  #pivot AA1-AA4 columns wider
  for(p in tolower(prcpDat)){
    #add number to names 
    wider_cols<-c("period_q","depth_dim","cond_code","qual_code")
    wider_cols<-glue('{wider_cols}_{substr(p,3,3)}')
    
    #convert depth dimension to mm and fill in missing data with NA based on coding from NOAA
    precipData<-precipData%>%
      tidyr::separate(col=all_of(p),into = wider_cols,sep=",",fill='right',convert=TRUE)%>%
      mutate(across(starts_with("depth_dim"), ~ if_else(.==9999,NA,./10)),
             across(starts_with("period_q"), ~ if_else(.==99,NA,.)),
      )
  }
  return(precipData)
}

#format date ranges YYYY-mm-dd HH:MM - YYYY-mm-dd HH:MM 
formatDT_NOAA<-function(dtRange){
  #date range has to be in format YYYY-mm-dd HH:MM - YYYY-mm-dd HH:MM 
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


#check if s3 bucket is avaialable
conf_buck<-function(bucket_arn,region){
  bucket_info<-bucket_exists(bucket=NOAMRMMS_bucket,region=region)
  bucket_check<-bucket_info[1]
  return(bucket_check)
}

#pulls gridded rast data from NOAAA MRMS for a specific datetime 
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
#This ultimately compiles gridded precipitation data from NOAA MRMS based on date_range vector
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

#pulls data from HDF5 files based on start time and end_time
#dates must be in YYYY-MM-DD format
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

#function to plot station time series data based on queried HDF5 file data

plot_station_ts <- function(event_ts) {
  #graph first accumulated reading
  p <- ggplot(event_ts, aes(x = date, y = depth_dim_1)) +
    geom_col(fill = "dodgerblue4", color = "black", width = 3600) + 
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
