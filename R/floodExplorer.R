source("R/helpers.R")

dcFlood_times<-read.csv("data/DC_flood_times.csv")

#check missing data in flood event data
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

#Create md table for Read me 
#knitr::kable(robustnessCheck,format='markdown')


#Washington Reagen had the most coverage of precipitation based on our flood events so we will pull 
#Pull station ID
dc_reagan<-noaa_nearby(lat=38.9007,lon=-77.0503)%>%
  filter(name=='WASHINGTON REAGAN NATL AP')%>%
  pull(station)

#ISD number for Washington Reagan had to be used for global hourly dataset 72405013743
#Pull all hourly data in one call then filter by flood time date ranges to save time



PRCPdataOBJ<-PRCP_stat(floodDt=dcFlood_times)
#Initialize date ranges vector so that we can compile raster data from flood events based on date ranges
date_ranges<-pull_dateRanges(dcFlood_times)

#Exploration Spatial data for DC

#Pull DC boundaries for gridded precipiation data
state_bounds<-states(cb=FALSE,class='sf')
sort(unique(state_bounds$NAME))
#found DC's name as District of Columbia
dc_bounds<-state_bounds%>%
  filter(NAME=='District of Columbia')
dc_vect<-vect(dc_bounds)
#create master dc_sample. This will be used later whe resampling data during compilation of gridded precipitation data
dc_sampling <- terra::rast(terra::ext(dc_vect), resolution = 0.01, crs = terra::crs(dc_vect))

# initialize arn and region of NOAA MRMS s3 bucket
NOAMRMMS_bucket<-"s3://noaa-mrms-pds/"
region<-"us-east-1"
bucket_check<-conf_buck(NOAMRMMS_bucket,region)


#compile PRCP from rasters
# Starting from flood event 99 since MRMS's earliest data is from 20201014/
#for project purposes, will only run on one flood event
sampleDCFloodevents<-date_ranges[100]

#run following code to run on all available date ranges
#sampleDCFloodevents<-date_ranges[99:125]

dcFloodPRCP<-compilePRCP(sampleDCFloodevents,conf_buck(NOAMRMMS_bucket,region))


#Create Rcreate HDF5 files
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
h5ls(h5_file)

station_meta <- rhdf5::h5readAttributes(h5_file, "station_TimeSeries/Washington National/ts_data")

meta_df <- data.frame(
  Attribute = names(station_meta),
  Value = sapply(gridded_meta, function(x) paste(x, collapse = ", ")),
  row.names = NULL
)
knitr::kable(meta_df, format = "markdown", col.names = c("Metadata Attribute", "Value / Description"))



#pull station data from 2020-10 to 2023-05
ts_station_data <- hdf5_stationQuery(h5_file, "1980-10-12", "2026-05-20")
print(head(event_data))

#example of available data range that can be pulled for
date_ranges<-'1996-01-01 00:00 - 2026-01-01 00:00'

#pull example date range from flood event and  pass items from that 
gridded_data <- hdf5_griddedQuery(h5_file, date_ranges)
print(gridded_data)


station_plot <- plot_station_ts(ts_station_data)
print(station_plot)

radar_plot <- plot_event_raster(gridded_data, dateRange="2020-11-12 04:00 - 2025-07-19 19:00",vect=dc_vect)
print(radar_plot)
