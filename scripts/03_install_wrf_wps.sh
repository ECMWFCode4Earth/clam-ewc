#!/bin/bash
set -eo pipefail

# ============================================================
# WRF 4.6.1 and WPS 4.6.0 installation script
#
# This script assumes that the third-party libraries are already
# installed by install_arw_third-party-libs.sh 
#
# Required:
#   $HOME/ARW/arw_intel_env.sh
#   $HOME/ARW/LIBRARIES
#   $HOME/ARW/JASPER-1.900.1
#
# Builds:
#   WRF 4.6.1
#   WPS 4.6.0
#
# Important choices based on successful build:
#   - WRF 4.6.1
#   - WRF dmpar with mpiifx/mpiicx
#   - WRF flags: -O3, no -ip
#   - WRF compile: -j 1
#   - WPS 4.6.0 serial
#   - WPS uses JasPer 1.900.1 for ungrib.exe
# ============================================================

export ARW_ROOT="${HOME}/ARW"
export DIR="${ARW_ROOT}/LIBRARIES"
export SRC="${ARW_ROOT}/src"

export WRF_VERSION="v4.6.1"
export WPS_VERSION="v4.6.0"

export WRF_DIR="${ARW_ROOT}/WRF-4.6.1"
export WPS_DIR="${ARW_ROOT}/WPS-4.6.0"
export JASPER19001="${ARW_ROOT}/JASPER-1.900.1"

if [ ! -f "${ARW_ROOT}/arw_intel_env.sh" ]; then
  echo "ERROR: ${ARW_ROOT}/arw_intel_env.sh not found."
  echo "Run install_arw_libraries.sh first."
  exit 1
fi

source "${ARW_ROOT}/arw_intel_env.sh"

echo "============================================================"
echo "ARW_ROOT     = ${ARW_ROOT}"
echo "LIBRARIES    = ${DIR}"
echo "WRF_DIR      = ${WRF_DIR}"
echo "WPS_DIR      = ${WPS_DIR}"
echo "JASPER19001  = ${JASPER19001}"
echo "============================================================"

echo "Checking required libraries..."

for f in \
  "${DIR}/lib/libz.so" \
  "${DIR}/lib/libpng16.so" \
  "${DIR}/lib/libhdf5.so" \
  "${DIR}/lib/libhdf5_fortran.so" \
  "${DIR}/lib/libnetcdf.so" \
  "${DIR}/lib/libnetcdff.so" \
  "${JASPER19001}/lib/libjasper.so.1"
do
  if [ ! -f "$f" ]; then
    echo "ERROR: required library not found:"
    echo "  $f"
    echo "Run install_arw_libraries.sh first."
    exit 1
  fi
done

echo "Checking netCDF:"
which nc-config
which nf-config
nc-config --prefix
nf-config --prefix
nc-config --has-nc4
nc-config --has-hdf5

echo "Checking compilers:"
which icx
which ifx
which mpiicx
which mpiifx

# ------------------------------------------------------------
# WRF 4.6.1
# ------------------------------------------------------------

cd "${ARW_ROOT}"

if [ ! -d "${WRF_DIR}/.git" ]; then
  echo "========== Cloning WRF 4.6.1 =========="
  rm -rf "${WRF_DIR}"
  git clone --branch "${WRF_VERSION}" --recursive https://github.com/wrf-model/WRF.git "${WRF_DIR}"
else
  echo "WRF source already exists: ${WRF_DIR}"
fi

cd "${WRF_DIR}"

git submodule update --init --recursive

echo "========== Configuring WRF =========="

./clean -a

echo
echo "When WRF asks for configuration, choose:"
echo "  Linux x86_64, Intel compiler, dmpar"
echo
echo "When WRF asks for nesting, choose:"
echo "  basic"
echo

./configure

# Force Intel MPI wrappers.
# On some systems, mpif90/mpicc from Intel MPI may default to GNU backends.
sed -i 's|^DM_FC.*|DM_FC           =       mpiifx|' configure.wrf
sed -i 's|^DM_CC.*|DM_CC           =       mpiicx|' configure.wrf

# Safer Intel build.
# The default -O3 -ip caused excessive memory usage in xfortcom.
sed -i 's/ -ip / /g' configure.wrf

echo "========== WRF configure summary =========="
grep -E "DESCRIPTION|SFC|SCC|DM_FC|DM_CC|NETCDF" configure.wrf

echo "========== Compiling WRF em_real =========="

./compile -j 1 em_real 2>&1 | tee compile_wrf_461_safe.log

echo "========== Checking WRF executables =========="

ls -lh main/real.exe main/wrf.exe

if [ ! -x main/real.exe ] || [ ! -x main/wrf.exe ]; then
  echo "ERROR: WRF executables were not created."
  exit 1
fi

# ------------------------------------------------------------
# WPS 4.6.0
# ------------------------------------------------------------

cd "${ARW_ROOT}"

if [ ! -d "${WPS_DIR}/.git" ]; then
  echo "========== Cloning WPS 4.6.0 =========="
  rm -rf "${WPS_DIR}"
  git clone --branch "${WPS_VERSION}" https://github.com/wrf-model/WPS.git "${WPS_DIR}"
else
  echo "WPS source already exists: ${WPS_DIR}"
fi

cd "${WPS_DIR}"

export WRF_DIR="${WRF_DIR}"
export NETCDF="${DIR}"
export JASPERLIB="${JASPER19001}/lib"
export JASPERINC="${JASPER19001}/include"

echo "========== Configuring WPS =========="

./clean -a

echo
echo "When WPS asks for configuration, choose:"
echo "  Linux x86_64, Intel compiler, serial"
echo
echo "WPS is usually built serial. WRF itself is built with MPI."
echo

./configure

sed -i "s|^WRF_DIR.*|WRF_DIR = ${WRF_DIR}|" configure.wps

# Use JasPer 1.900.1 for ungrib.exe.
sed -i "s|^COMPRESSION_LIBS.*|COMPRESSION_LIBS    = -L${JASPER19001}/lib -ljasper -L${DIR}/lib -lpng -lz|" configure.wps
sed -i "s|^COMPRESSION_INC.*|COMPRESSION_INC     = -I${JASPER19001}/include -I${DIR}/include|" configure.wps

echo "========== WPS configure summary =========="
grep -E "SFC|SCC|DM_FC|DM_CC|WRF_DIR|NETCDF|JASPER|COMPRESSION" configure.wps

echo "========== Compiling WPS =========="

./compile 2>&1 | tee compile_wps_460.log

echo "========== Checking WPS executables =========="

ls -lh geogrid.exe ungrib.exe metgrid.exe

if [ ! -x geogrid.exe ] || [ ! -x ungrib.exe ] || [ ! -x metgrid.exe ]; then
  echo "ERROR: WPS executables were not created."
  exit 1
fi

echo "========== Checking ungrib runtime libraries =========="

ldd ungrib.exe | grep -E "jasper|png|z|imf|svml" || true

if ldd ungrib.exe | grep -q "not found"; then
  echo "ERROR: ungrib.exe has missing runtime libraries."
  exit 1
fi

echo
echo "============================================================"
echo "WRF and WPS installed successfully."
echo
echo "WRF directory:"
echo "  ${WRF_DIR}"
echo
echo "WPS directory:"
echo "  ${WPS_DIR}"
echo
echo "To load the environment:"
echo "  source ${ARW_ROOT}/arw_intel_env.sh"
echo "============================================================"
