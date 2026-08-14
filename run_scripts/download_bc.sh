#!/bin/bash

# Download pre-MTG2 data from operational model of ECMWF following instructions from:
# https://confluence.ecmwf.int/spaces/DAC/pages/228871388/Test+data+for+the+US+Weather+Research+and+Forecasting+WRF+model

set -e

cd /data/ARW/BC
wget ftp://anonymous@bolftp.ecmwf.int/public/wrf/EUROPE/ECMWF_*_europe.tar.gz

for f in ECMWF_*_europe.tar.gz; do
    tar -zxvf "$f"
done

rm ECMWF_*_europe.tar.gz
