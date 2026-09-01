#!/bin/bash

set -xe

CYC=00 # initialisation time
FLENGTH=6 # wrf forecast lenght

export RUN_DATE=20180601

export ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"

export ENV_FILE="$ARW_ROOT/arw_intel_env.sh"

export RUN_CYCLE=${RUN_DATE}${CYC}
export RUN_LOC=${RUN_CYCLE}_europe
export RUN_DIR=$ARW_ROOT/RUNS/${RUN_LOC}

if [ -d "${RUN_DIR}" ]; then
  rm -rf ${RUN_DIR}
fi
mkdir -p ${RUN_DIR}

START_DATE=$RUN_CYCLE
START_YY=`echo $START_DATE | cut -c 1-4`
START_MM=`echo $START_DATE | cut -c 5-6`
START_DD=`echo $START_DATE | cut -c 7-8`
START_HH=`echo $START_DATE | cut -c 9-10`

WPS_START_DATE=${START_YY}-${START_MM}-${START_DD}_${START_HH}:00:00
WPS_END_DATE=`date -d "$RUN_DATE $CYC $FLENGTH hours" +%Y-%m-%d_%H:00:00`
END_YY=`echo $WPS_END_DATE | cut -c 1-4`
END_MM=`echo $WPS_END_DATE | cut -c 6-7`
END_DD=`echo $WPS_END_DATE | cut -c 9-10`
END_HH=`echo $WPS_END_DATE | cut -c 12-13`

export GEOG=$ARW_ROOT/GEOG/WPS_GEOG

cat namelist.wps.in | sed s/_WPS_START_DATE_/$WPS_START_DATE/ | \
                      sed s,_GEOG_PATH_,$GEOG, | \
                      sed s/_WPS_END_DATE_/$WPS_END_DATE/ > ${RUN_DIR}/namelist.wps

cat namelist.input.in | sed s/_FLENGTH_/$FLENGTH/ | \
                        sed s/_START_YY_/$START_YY/ | \
                        sed s/_START_MM_/$START_MM/ | \
                        sed s/_START_DD_/$START_DD/ | \
                        sed s/_START_HH_/$START_HH/ | \
                        sed s/_END_YY_/$END_YY/ | \
                        sed s/_END_MM_/$END_MM/ | \
                        sed s/_END_DD_/$END_DD/ | \
                        sed s/_END_HH_/$END_HH/ > ${RUN_DIR}/namelist.input.clam

ln -sf $ARW_ROOT/BC/ECMWF_${START_YY}${START_MM}${START_DD}_${CYC}*.grb ${RUN_DIR}/

cat run_wps.sh.in  | sed s,_WRF_,$ARW_ROOT, | \
                     sed s,_RUN_DIR_,$RUN_DIR, > ${RUN_DIR}/run_wps.sh
cat run_real.sh.in | sed s,_RUN_DIR_,$RUN_DIR, | \
                     sed s,_WRF_,$ARW_ROOT, > ${RUN_DIR}/run_real.sh
cat run_wrf.sh.in | sed s,_RUN_DIR_,$RUN_DIR, | \
                    sed s,_WRF_,$ARW_ROOT, > ${RUN_DIR}/run_wrf.sh
cat run_wrf_multiVMs.sh.in | sed s,_RUN_DIR_,$RUN_DIR, | \
                             sed s,_WRF_,$ARW_ROOT, > ${RUN_DIR}/run_wrf_multiVMs.sh

cd ${RUN_DIR}
bash run_wps.sh
