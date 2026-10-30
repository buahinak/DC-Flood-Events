
How to run this project:

Info on Data sources

Based on the flood event datasets in DC, I am pulling precipitation data from 2 sources:
  
  Weather Station data in the DC area
  NOAA MRMS

To investigate the stations in the area, I found 25 stations nearby Foggy Bottom Metro station at the following coordinates: lat=38.9007,lon=-77.0503. I used the readnoaa package in R to find these nearby stations.I also checked for precipitation data availability for the 25 stations that I found.

Washington Reagan had the most robust precipiation time series data as it covers 86 years of flood precipitation from 1941-2026.

Robustness Check for NOAA station precipitation data
DCA Reagan

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

Dictionary for added columns in station precipitation data
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