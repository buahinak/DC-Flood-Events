
## How to use this project:
- Download project to local machine 
- Open zip file and open DC Flood Events.rproj.
- This project uses renv to track packages and dependencies 
- Create a /data folder in the main project directory and place DC_flood_times.csv in that folder. This will be very important for the analysis portion of this project
- Run renv::restore() after you have opened the project in your R console.

**Other important info**
- Main analysis script can be found in /R folder in floodExplorer.R
- R/helpers.R has all functions used for analysis this is 
- helpers.R is sourced in floodExplorer.R
- If you have issues installing rhdf5, try running the following code in console 
    install.packages("BiocManager")
    BiocManager::install('rhdf5')
- I have included the figures I made through my analysis since they are very small png files(2 png files)

## ACKNOWLEDGEMENT OF AI USE:
Gemini was used for programming, debugging and speeding up code, explaining spatial data and creating visualizations for this project. AI was not used for documentation of code or construction of this readme FILE

## Data Sources:
Based on the flood event datasets in DC, I am pulling precipitation data from 2 sources:
  
  **Weather Station data in the DC area**
  **NOAA MRMS**

To investigate the NOAA weather stations in the area, I found 25 stations nearby Foggy Bottom Metro station at the following coordinates: latitude=38.9007,longitude=-77.0503. I used the readnoaa package in R to find these nearby stations.I also checked for precipitation data availability for the 25 stations that I found.

Washington Reagan had the most robust precipitation time series data as it covers 86 years of flood precipitation from 1941-2026.

**Robustness Check for NOAA station precipitation data at DCA Reagan**

|station     |element | first_year| last_year| years|name                      |
|:-----------|:-------|----------:|---------:|-----:|:-------------------------|
|USW00093725 |PRCP    |       1852|      1965|   114|WASHINGTON                |
|USC00189674 |PRCP    |       1860|      1866|     7|GEORGETOWN                |
|US1DCDC0019 |PRCP    |       2015|      2018|     4|THE WHITE HOUSE           |
|US1DCDC0015 |PRCP    |       2011|      2020|    10|WASHINGTON 1.9 WNW        |
|USC00441729 |PRCP    |       1925|      1962|    38|CLARENDON LYON PARK       |
|US1DCDC0034 |PRCP    |       2018|      2023|     6|WASHINGTON 1.9 NW         |
|US1DCDC0009 |PRCP    |       2008|      2026|    19|WASHINGTON 2.0 SSW        |
|US1DCDC0045 |PRCP    |       2025|      2026|     2|WASHINGTON 2.0 NNW        |
|US1DCDC0043 |PRCP    |       2024|      2026|     3|WASHINGTON 0.9 ESE        |
|US1DCDC0011 |PRCP    |       2008|      2010|     3|WASHINGTON 4.0 WNW        |
|US1DCDC0007 |PRCP    |       2007|      2007|     1|WASHINGTON 1.2 SE         |
|USC00189035 |PRCP    |       1948|      1977|    30|US SOLDIERS HOME DC       |
|US1VAAR0008 |PRCP    |       2014|      2026|    13|ARLINGTON 0.3 E           |
|US1VAAR0005 |PRCP    |       2006|      2010|     5|ALEXANDRIA 2.4 NE         |
|US1DCDC0044 |PRCP    |       2025|      2026|     2|WASHINGTON 2.4 N          |
|USC00440449 |PRCP    |       1945|      1949|     5|BARCROFT                  |
|US1DCDC0008 |PRCP    |       2007|      2008|     2|WASHINGTON 2.0 ESE        |
|USW00013751 |PRCP    |       1945|      1956|    12|ANACOSTIA NAS             |
|US1DCDC0006 |PRCP    |       2007|      2007|     1|WASHINGTON 2.0 ESE        |
|US1DCDC0003 |PRCP    |       2006|      2006|     1|WASHINGTON 5.0 WNW        |
|US1VAAR0006 |PRCP    |       2007|      2010|     4|ARLINGTON 1.1 NW          |
|USC00448938 |PRCP    |       1945|      1970|    26|WAVERLY HILLS             |
|USW00013743 |PRCP    |       1941|      2026|    86|WASHINGTON REAGAN NATL AP |
|USC00181135 |PRCP    |       1944|      1956|    13|BRIGHTWOOD DC             |
|US1DCDC0040 |PRCP    |       2022|      2026|     5|WASHINGTON 2.2 ESE        |

**Summary Stats for Washington Reagan Precipitation Data**

|   |  station        |    name         |   latitude   |  longitude    |  elevation   |     date                      |   source        |report_type      | call_sign       |quality_control  |  period_q_1   | depth_dim_1   | cond_code_1  |qual_code_1      |  period_q_2   | depth_dim_2   | cond_code_2  | qual_code_2 |  period_q_3  | depth_dim_3   | cond_code_3 | qual_code_3  |  period_q_4 | depth_dim_4  | cond_code_4 | qual_code_4 | date_char       |
|:--|:----------------|:----------------|:-------------|:--------------|:-------------|:------------------------------|:----------------|:----------------|:----------------|:----------------|:--------------|:--------------|:-------------|:----------------|:--------------|:--------------|:-------------|:------------|:-------------|:--------------|:------------|:-------------|:------------|:-------------|:------------|:------------|:----------------|
|   |Length:2157      |Length:2157      |Min.   :38.85 |Min.   :-77.03 |Min.   :3.000 |Min.   :1996-01-19 11:00:00.00 |Length:2157      |Length:2157      |Length:2157      |Length:2157      |Min.   : 1.000 |Min.   :0.0000 |Min.   :2.000 |Length:2157      |Min.   : 3.000 |Min.   :0.0000 |Min.   :2.000 |Min.   :1.0  |Min.   : 6.00 |Min.   : 0.000 |Min.   :9    |Min.   :1.000 |Min.   : NA  |Min.   : 7.00 |Min.   :9    |Min.   :1    |Length:2157      |
|   |Class :character |Class :character |1st Qu.:38.85 |1st Qu.:-77.03 |1st Qu.:3.000 |1st Qu.:2005-04-02 11:51:00.00 |Class :character |Class :character |Class :character |Class :character |1st Qu.: 1.000 |1st Qu.:0.0000 |1st Qu.:3.000 |Class :character |1st Qu.: 3.000 |1st Qu.:0.0030 |1st Qu.:9.000 |1st Qu.:1.0  |1st Qu.:24.00 |1st Qu.: 0.250 |1st Qu.:9    |1st Qu.:1.000 |1st Qu.: NA  |1st Qu.:15.97 |1st Qu.:9    |1st Qu.:1    |Class :character |
|   |Mode  :character |Mode  :character |Median :38.85 |Median :-77.03 |Median :3.000 |Median :2014-04-30 22:36:00.00 |Mode  :character |Mode  :character |Mode  :character |Mode  :character |Median : 1.000 |Median :0.0018 |Median :9.000 |Mode  :character |Median : 6.000 |Median :0.0850 |Median :9.000 |Median :1.0  |Median :24.00 |Median : 1.420 |Median :9    |Median :1.000 |Median : NA  |Median :24.95 |Median :9    |Median :1    |Mode  :character |
|   |                 |                 |Mean   :38.85 |Mean   :-77.03 |Mean   :3.151 |Mean   :2011-12-11 06:38:42.42 |                 |                 |                 |                 |Mean   : 1.638 |Mean   :0.0051 |Mean   :6.222 |                 |Mean   : 6.271 |Mean   :0.1708 |Mean   :8.403 |Mean   :1.1  |Mean   :21.43 |Mean   : 3.098 |Mean   :9    |Mean   :1.054 |Mean   :NaN  |Mean   :24.95 |Mean   :9    |Mean   :1    |                 |
|   |                 |                 |3rd Qu.:38.85 |3rd Qu.:-77.03 |3rd Qu.:3.000 |3rd Qu.:2018-11-24 19:52:00.00 |                 |                 |                 |                 |3rd Qu.: 1.000 |3rd Qu.:0.0058 |3rd Qu.:9.000 |                 |3rd Qu.: 6.000 |3rd Qu.:0.2218 |3rd Qu.:9.000 |3rd Qu.:1.0  |3rd Qu.:24.00 |3rd Qu.: 4.670 |3rd Qu.:9    |3rd Qu.:1.000 |3rd Qu.: NA  |3rd Qu.:33.92 |3rd Qu.:9    |3rd Qu.:1    |                 |
|   |                 |                 |Max.   :38.85 |Max.   :-77.03 |Max.   :4.100 |Max.   :2025-07-19 18:00:00.00 |                 |                 |                 |                 |Max.   :24.000 |Max.   :0.1318 |Max.   :9.000 |                 |Max.   :24.000 |Max.   :1.8010 |Max.   :9.000 |Max.   :9.0  |Max.   :24.00 |Max.   :18.010 |Max.   :9    |Max.   :2.000 |Max.   : NA  |Max.   :42.90 |Max.   :9    |Max.   :1    |                 |
|   |                 |                 |              |               |              |                               |                 |                 |                 |                 |NA's   :411    |NA's   :411    |NA's   :411   |                 |NA's   :1936   |NA's   :1937   |NA's   :1936  |NA's   :1936 |NA's   :2122  |NA's   :2120   |NA's   :2120 |NA's   :2120  |NA's   :2157 |NA's   :2155  |NA's   :2155 |NA's   :2155 |                 |

** NOAA MRMS Precipitation data
    
Data was pulled from the NOAA MRMS AWS S3 open bucket which can be explored in browser here: https://noaa-mrms-pds.s3.amazonaws.com/index.html
Documentation on bucket's info can be found here: https://registry.opendata.aws/noaa-mrms-pds/

I explored the bucket in browser to devise a reproducible way to pull MRMS data. I found the Precip Rate, Precip Flag and MultiSensorQPE data in the bucket. I initially combed through Precip rate data. The data was too detailed however, because there is precipitation data every 2 minutes. The MultiSensorQPE 1H dataset was the best fit computationally since I could pull accumulated precipitation data for every hour instead of every 2 minutes.I used MultiSensor_QPE_01H_Pass2_00.00 instead of MultiSensor_QPE_01H_Pass1_00.00 because Pass2 captures 99% of available rain gauges over 2 hours instead of 1(https://vlab.noaa.gov/web/wdtd/-/multi-sensor-qpe). The S3 bucket only has precipitation data from October 14 2020 to current day. 

 There was initial difficulty with accessing these files thorugh R. First method to get data into are was to save the data into memory using a temporary file then rasterizing it using the terra package. I found that the easiest method would be to read the image remotely using GDAL VSI prefix(/vsigzip//vsicurl/ ) before referring to the files. Documentation  at https://gdal.org/en/stable/user/virtual_file_systems.html was helpful for this. I created functions to find each hour within a specified date and format the date into a file structure that could be looped over. Exploring the s3 bucket through html in my browser was integral for this.I used Gemini to help me translate code from documentation into actionable R code. I also found difficulty in programming code that was fast. I used Gemini to help me debug and speed up slow date parsing code.
Data Missingness
In addition to data prior to October 14 2020 being unavailable, data from September 16 2021 8:00-9:00 P.M UTC is unavailable in the s3 bucket.

## Data Manipulation

AA1-AA4 precipitation data was pulled from NOAA. Info on these readings can be found on pg 13 of the    following documentation : https://www.ncei.noaa.gov/pub/data/noaa/isd-format-document.pdf 
  
  Separated the readings from the 4 accumulated readings and created new variables that can be found in   the HDF5 dataset
  n=[1,2,3,4]
  period_q_n: LIQUID-PRECIPITATION period quantity for nth accumulation
  depth_dim_n: LIQUID-PRECIPITATION depth dimension for nth accumulation in mm
  cond_code_n: LIQUID-PRECIPITATION condition code for nth accumulation
  qual_code_n : LIQUID-PRECIPITATION quality code for nth accumulation
  
  depth_dim_n was divided by 10 to get the resulting value
  Missing values for period quantity(coded as 99 in actual data) are NA in dataset
  Missing values for depth dimension(coded as 9999 in actual data) are NA in dataset

No data manipulation was performed on the gridded precipitation data. Metadata features were added to both gridded precipitation data and station data.

## HDF5 File Structure

An HDF5 file with all collectible flood event data can be found in the data/ folder of this project. The layered structure for the HDF5 file is as follows

**Structure**:
                                    group                  name       otype   dclass           dim
0                                       / gridded_precipitation   H5I_GROUP                       
1                  /gridded_precipitation            NOAAA MRMS   H5I_GROUP                       
2       /gridded_precipitation/NOAAA MRMS      QPE_01HOURS_data H5I_DATASET    FLOAT 20 x 21 x 156
3                                       /    station_TimeSeries   H5I_GROUP                       
4                     /station_TimeSeries   Washington National   H5I_GROUP                       
5 /station_TimeSeries/Washington National               ts_data H5I_DATASET COMPOUND          2157

The data set is  split into station time series(station_TimeSeries) group and gridded precipitation(gridded_precipitation) group. This structure allows for possible extension to other gridded precipitation sources like PRISM being added to the group in addition to the NOAA MRMS and other stations around DC to be added to the station time series group. I used Gemini for programming assistance in developing the HDF5 saving pipeline. Since I am not very familiar with spatial data , I used Gemini to program visualizations of the gridded precipitation data and the station time series data.
The following is the metadata associated with the station time series and gridded precipitation data.

**NOAA Station Precipitation Metadata:**

|Metadata Attribute       |Value / Description                                                    |
|:------------------------|:----------------------------------------------------------------------|
|Coordinates              |38.8472,-77.0344                                                       |
|Precipitation Collection |HOURLY ACCUMULATION OF LIQUID PRECIPITATION. SOME EVENTS HAVE >AN HOUR |
|Station ID               |USW00013743                                                            |
|Units                    |mm                                                                     |

**NOAA MRMRS Gridded Precipitation Metadata:**

class       : SpatRaster
size        : 20, 21, 156  (nrow, ncol, nlyr)
resolution  : 0.01001743, 0.01021  (x, y)
extent      : -77.11976, -76.90939, 38.79165, 38.99585  (xmin, xmax, ymin, ymax)
coord. ref. : lon/lat Coordinate System imported from GRIB file
source(s)   : memory
names       : Multi~-GPML, Multi~-GPML, Multi~-GPML, Multi~-GPML, Multi~-GPML, Multi~-GPML, ...
min values  :           2,         4.5,         0.4,         0.3,         1.5,           0, ...
max values  :          16,        31.1,           9,         7.7,         7.3,         1.3, ...
time        : 2020-11-12 04:00:00zUTC to 2025-07-19 19:00:00zUTC (153 steps)
Precipitation Collection
[1] "HOURLY ACCUMULATION OF LIQUIDPRECIPITATION"
Time Index(UTC)`
