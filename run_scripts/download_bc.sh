#!/bin/bash

# Download pre-MTG2 data from operational model of ECMWF following instructions from:
# https://confluence.ecmwf.int/spaces/DAC/pages/228871388/Test+data+for+the+US+Weather+Research+and+Forecasting+WRF+model

set -e

export ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"

if [ ! -d "$ARW_ROOT/BC" ]; then
    mkdir -p "$ARW_ROOT/BC"
fi

cd $ARW_ROOT/BC

# Select your domain where possible options are:
# AFRICA
# ASIA
# AUSTRALIA
# EUROPE
# NORTH_AMERICA
# SOUTH_AMERICA

DOMAIN="EUROPE"

if [ "$DOMAIN" = "EUROPE" ]; then
        domain="europe"
elif [ "$DOMAIN" = "AFRICA" ]; then
	domain="africa"
elif [ "$DOMAIN" = "ASIA" ]; then
	domain="asia"
elif [ "$DOMAIN" = "AUSTRALIA" ]; then
	domain="australia"
elif [ "$DOMAIN" = "NORTH_AMERICA" ]; then
	domain="north_america"
elif [ "$DOMAIN" = "SOUTH_AMERICA" ]; then
	domain="south_america"
fi

wget ftp://anonymous@bolftp.ecmwf.int/public/wrf/$DOMAIN/ECMWF_*_${domain}.tar.gz

for f in ECMWF_*_${domain}.tar.gz; do
    tar -zxvf "$f"
done

rm ECMWF_*_${domain}.tar.gz
