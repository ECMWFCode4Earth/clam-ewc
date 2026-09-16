#!/bin/bash

# Download GRIB2 Open Data from operational model of ECMWF following instructions from:
# https://www.ecmwf.int/en/forecasts/datasets/open-data

set -e

export ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"

# Normally passed in by main_wrf.sh. The defaults make the script usable
# on its own, e.g.
#   RUN_DATE=20260916 CYC=00 FLENGTH=6 ./download_bc.sh
RUN_DATE="${RUN_DATE:-$(date -u +%Y%m%d)}"
CYC="${CYC:-00}"
FLENGTH="${FLENGTH:-6}"

# ECMWF open data oper 0p25 is published on a 3 hourly step, which is
# also the interval_seconds = 10800 used in namelist.wps.in.
STEP_HOURS="${STEP_HOURS:-3}"

BASE_URL="https://data.ecmwf.int/forecasts/${RUN_DATE}/${CYC}z/ifs/0p25/oper"

echo "============================================================"
echo "RUN_DATE    = ${RUN_DATE}"
echo "CYC         = ${CYC}"
echo "FLENGTH     = ${FLENGTH} hours"
echo "STEP_HOURS  = ${STEP_HOURS}"
echo "BASE_URL    = ${BASE_URL}"
echo "TARGET      = ${ARW_ROOT}/BC"
echo "============================================================"

if [ ! -d "$ARW_ROOT/BC" ]; then
    mkdir -p "$ARW_ROOT/BC"
fi

cd $ARW_ROOT/BC

# Downloads $1 to $2 via a temporary file, so that an interrupted
# transfer never leaves a truncated GRIB file behind for ungrib to read.
download_file() {
  _url="$1"
  _dest="$2"
  _tmp="${_dest}.download"

  rm -f "${_tmp}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${_tmp}" "${_url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${_tmp}" "${_url}"
  else
    echo "ERROR: neither curl nor wget is available to download"
    echo "  ${_url}"
    return 1
  fi

  if [ ! -s "${_tmp}" ]; then
    echo "ERROR: downloaded file is empty:"
    echo "  ${_url}"
    rm -f "${_tmp}"
    return 1
  fi

  mv "${_tmp}" "${_dest}"
}

# ECMWF open data is packed with CCSDS (packingType = grid_ccsds),
# which the GRIB2 decoder in WPS ungrib cannot read, so every file is
# repacked to grid_simple with ecCodes before ungrib sees it.
if ! command -v grib_set >/dev/null 2>&1; then
  echo "ERROR: grib_set not found in PATH."
  echo "ecCodes is required to repack the CCSDS packed open data."
  echo "Install it with build_scripts/05_install_eccodes.sh, or add"
  echo "an existing installation to PATH."
  exit 1
fi

# Repacks $1 to packingType = grid_simple if any of its messages are
# still CCSDS packed, and does nothing otherwise.
#
# The decision is taken from the packing of the file itself, not from
# whether it was just downloaded, so that files left behind by an
# earlier run, or by a version of this script without this step, are
# converted as well.
#
# grib_set cannot work in place, hence the .repack temporary. It is
# named so that it stays out of the <date>_<cycle>*.grib2 glob that
# main_wrf.sh links into the run directory.
repack_to_grid_simple() {
  _file="$1"
  _types="$(grib_get -p packingType "${_file}" 2>/dev/null | sort -u || true)"

  if [ -z "${_types}" ]; then
    echo "ERROR: no GRIB messages could be read from ${_file}"
    echo "The file may be truncated. Remove it and re-run."
    return 1
  fi

  case "${_types}" in
    *grid_ccsds*) ;;
    *)
      echo "Already unpacked, no CCSDS messages: ${_file}"
      return 0
      ;;
  esac

  echo "Repacking grid_ccsds -> grid_simple: ${_file}"

  # Messages that are not CCSDS packed are copied through unchanged.
  if ! grib_set -r -w packingType=grid_ccsds -s packingType=grid_simple \
    "${_file}" "${_file}.repack"; then
    echo "ERROR: grib_set failed to repack ${_file}."
    echo "The original file is left untouched."
    rm -f "${_file}.repack"
    return 1
  fi

  if [ ! -s "${_file}.repack" ]; then
    echo "ERROR: repacked file is empty: ${_file}.repack"
    rm -f "${_file}.repack"
    return 1
  fi

  mv "${_file}.repack" "${_file}"
}

# One file per forecast step, from the analysis (0h) out to FLENGTH.
# The local names match the <date>_<cycle>*.grib2 pattern that
# main_wrf.sh links into the run directory.
STEP=0
DOWNLOADED=0

while [ "${STEP}" -le "${FLENGTH}" ]; do
  REMOTE="${RUN_DATE}${CYC}0000-${STEP}h-oper-fc.grib2"
  LOCAL="$(printf '%s_%s_%03dh.grib2' "${RUN_DATE}" "${CYC}" "${STEP}")"

  if [ -s "${LOCAL}" ]; then
    echo "Already downloaded: ${LOCAL}"
  else
    echo "Downloading ${REMOTE} -> ${LOCAL}"
    if ! download_file "${BASE_URL}/${REMOTE}" "${LOCAL}"; then
      echo "ERROR: could not download forecast step ${STEP}h:"
      echo "  ${BASE_URL}/${REMOTE}"
      echo "ECMWF open data keeps only the most recent days, and the"
      echo "${CYC}z cycle of ${RUN_DATE} may not be published yet."
      exit 1
    fi
  fi

  # Checked on every run, including for files downloaded earlier.
  if ! repack_to_grid_simple "${LOCAL}"; then
    exit 1
  fi

  DOWNLOADED=$((DOWNLOADED + 1))
  STEP=$((STEP + STEP_HOURS))
done

echo "========== Boundary condition files =========="
ls -lh ${RUN_DATE}_${CYC}_*.grib2
echo "${DOWNLOADED} file(s) available for ${RUN_DATE} ${CYC}z, 0h to ${FLENGTH}h,"
echo "repacked to packingType = grid_simple."
