#!/bin/bash

# Download "Mandatory Static Data" from:
# https://www2.mmm.ucar.edu/wrf/users/download/get_sources_wps_geog.html#mandatory
# Note this will download the highest resolution, there is also an option to download the lowest resolution

set -e

export ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"

if [ ! -d "$ARW_ROOT/GEOG" ]; then
    mkdir -p "$ARW_ROOT/GEOG"
fi

cd $ARW_ROOT/GEOG

wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz

tar -zxvf geog_high_res_mandatory.tar.gz

rm geog_high_res_mandatory.tar.gz
