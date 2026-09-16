#!/bin/bash
#=================================================================
# OPTIONAL: install ecCodes system wide (default /usr/local).
#
# ecCodes is ECMWF's GRIB/BUFR decoding library and command line
# toolset (grib_ls, grib_dump, grib_copy, grib_to_netcdf, ...).
# It is NOT required to build or run WRF/WPS: WPS decodes GRIB2
# with its own g2lib/JasPer. ecCodes is used to inspect and
# manipulate the ECMWF open data GRIB2 boundary condition files.
#
#   ecCodes home:    https://confluence.ecmwf.int/spaces/ECC/pages/25107922/ecCodes+Home
#   Releases:        https://confluence.ecmwf.int/spaces/ECC/pages/45757960/Releases
#   Installation:    https://confluence.ecmwf.int/spaces/ECC/pages/45757987/ecCodes+installation
#
# This script needs sudo for the apt dependencies and for
# "make install" into the system prefix.
#
# Built with the system GNU compilers, on purpose: ecCodes is used
# here as a standalone diagnostic tool, so it is kept independent of
# the Intel oneAPI build of WRF/WPS and of the NetCDF/HDF5 stack in
# ${ARW_ROOT}/LIBRARIES.
#
# Overridable from the environment:
#   ECCODES_VERSION    release to install                (default 2.48.0)
#   ECCODES_PREFIX     install prefix                    (default /usr/local)
#   ECCODES_SRC        build/source directory            (default ${HOME}/ARW/src)
#   ECCODES_RUN_TESTS  run ctest after the build         (default 1)
#   ECCODES_JOBS       parallel build jobs               (default nproc)
#   ECCODES_WITH_AEC   build libaec and enable CCSDS     (default 1)
#   LIBAEC_VERSION     libaec release to build           (default 1.1.4)
#
# Example:
#   ECCODES_VERSION=2.48.0 ECCODES_PREFIX=/opt/eccodes ./05_install_eccodes.sh
#=================================================================

set -eo pipefail

ECCODES_VERSION="${ECCODES_VERSION:-2.48.0}"
ECCODES_PREFIX="${ECCODES_PREFIX:-/usr/local}"
ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"
ECCODES_SRC="${ECCODES_SRC:-${ARW_ROOT}/src}"
ECCODES_RUN_TESTS="${ECCODES_RUN_TESTS:-1}"
ECCODES_JOBS="${ECCODES_JOBS:-$(nproc)}"
ECCODES_WITH_AEC="${ECCODES_WITH_AEC:-1}"
LIBAEC_VERSION="${LIBAEC_VERSION:-1.1.4}"

ECCODES_TARBALL="eccodes-${ECCODES_VERSION}-Source.tar.gz"
# The release tarballs are Confluence attachments of the Releases page.
ECCODES_URL="https://confluence.ecmwf.int/download/attachments/45757960/${ECCODES_TARBALL}"

SRC_DIR="${ECCODES_SRC}/eccodes-${ECCODES_VERSION}-Source"
BUILD_DIR="${ECCODES_SRC}/eccodes-${ECCODES_VERSION}-build"

echo "============================================================"
echo "ECCODES_VERSION = ${ECCODES_VERSION}"
echo "ECCODES_PREFIX  = ${ECCODES_PREFIX}"
echo "ECCODES_SRC     = ${ECCODES_SRC}"
echo "ECCODES_URL     = ${ECCODES_URL}"
echo "RUN_TESTS       = ${ECCODES_RUN_TESTS}"
echo "JOBS            = ${ECCODES_JOBS}"
echo "WITH_AEC        = ${ECCODES_WITH_AEC} (libaec ${LIBAEC_VERSION})"
echo "============================================================"

# ------------------------------------------------------------
# Dependencies
#
# CMake is not installed by 00_install_system_packages.sh. ecCodes
# 2.48.0 needs CMake 3.12 or newer and libaec 1.1.4 or newer needs
# 3.26, both satisfied by the 3.28 that Ubuntu 24.04 ships.
#
# openjpeg: JPEG2000 packing, used by ECMWF GRIB2 products
# libpng  : PNG packing
# netcdf  : grib_to_netcdf. This is the system GNU NetCDF and is
#           unrelated to the Intel built NetCDF used by WRF/WPS.
#
# libaec is deliberately NOT taken from apt: ecCodes 2.48.0 does a
# find_package( libaec 1.1.4 ) and Ubuntu 24.04 only has 1.1.2, so
# the distribution package would leave CCSDS support disabled. It is
# built from source below instead.
# ------------------------------------------------------------

echo "========== Installing ecCodes build dependencies =========="

sudo apt update

sudo apt install -y \
  cmake \
  build-essential \
  gfortran \
  libopenjp2-7-dev \
  libpng-dev \
  libnetcdf-dev

echo "========== CMake version =========="
cmake --version | head -n 1

# ------------------------------------------------------------
# libaec (CCSDS / AEC packing)
#
# Required for ecCodes to read GRIB2 messages with
# packingType = grid_ccsds, which ECMWF uses for many products.
# ecCodes itself calls this "highly recommended" and its configure
# step aborts when libaec is missing and ENABLE_AEC is not set.
# Installed into the same prefix as ecCodes.
# ------------------------------------------------------------

mkdir -p "${ECCODES_SRC}"

if [ "${ECCODES_WITH_AEC}" = "1" ]; then
  LIBAEC_TARBALL="libaec-${LIBAEC_VERSION}.tar.gz"
  LIBAEC_URL="https://github.com/MathisRosenhauer/libaec/releases/download/v${LIBAEC_VERSION}/${LIBAEC_TARBALL}"
  LIBAEC_SRC_DIR="${ECCODES_SRC}/libaec-${LIBAEC_VERSION}"
  LIBAEC_BUILD_DIR="${ECCODES_SRC}/libaec-${LIBAEC_VERSION}-build"

  echo "========== Installing libaec ${LIBAEC_VERSION} =========="

  cd "${ECCODES_SRC}"

  if [ ! -s "${LIBAEC_TARBALL}" ]; then
    rm -f "${LIBAEC_TARBALL}.download"
    if ! curl -fsSL -o "${LIBAEC_TARBALL}.download" "${LIBAEC_URL}"; then
      echo "ERROR: could not download ${LIBAEC_URL}"
      echo "Re-run with ECCODES_WITH_AEC=0 to build ecCodes without"
      echo "CCSDS support, or with a different LIBAEC_VERSION."
      rm -f "${LIBAEC_TARBALL}.download"
      exit 1
    fi
    mv "${LIBAEC_TARBALL}.download" "${LIBAEC_TARBALL}"
  fi

  rm -rf "${LIBAEC_SRC_DIR}" "${LIBAEC_BUILD_DIR}"
  tar -xzf "${LIBAEC_TARBALL}"

  mkdir -p "${LIBAEC_BUILD_DIR}"
  cd "${LIBAEC_BUILD_DIR}"

  cmake \
    -DCMAKE_INSTALL_PREFIX="${ECCODES_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    "${LIBAEC_SRC_DIR}"

  make -j "${ECCODES_JOBS}"
  sudo make install
  sudo ldconfig

  ECCODES_AEC_FLAG="-DENABLE_AEC=ON"
else
  echo "========== Skipping libaec (ECCODES_WITH_AEC=0) =========="
  echo "WARNING: ecCodes will not decode packingType = grid_ccsds."
  ECCODES_AEC_FLAG="-DENABLE_AEC=OFF"
fi

# ------------------------------------------------------------
# Download
# ------------------------------------------------------------

cd "${ECCODES_SRC}"

if [ -s "${ECCODES_TARBALL}" ]; then
  echo "Tarball already present: ${ECCODES_SRC}/${ECCODES_TARBALL}"
else
  echo "========== Downloading ecCodes ${ECCODES_VERSION} =========="
  # Downloaded to a temporary name first, so an interrupted transfer
  # is not mistaken for a complete tarball on the next run.
  rm -f "${ECCODES_TARBALL}.download"
  if ! curl -fsSL -o "${ECCODES_TARBALL}.download" "${ECCODES_URL}"; then
    echo "ERROR: could not download ${ECCODES_URL}"
    echo "Check the current release number on"
    echo "  https://confluence.ecmwf.int/spaces/ECC/pages/45757960/Releases"
    echo "and re-run with, for example, ECCODES_VERSION=2.48.0"
    rm -f "${ECCODES_TARBALL}.download"
    exit 1
  fi
  mv "${ECCODES_TARBALL}.download" "${ECCODES_TARBALL}"
fi

echo "========== Unpacking =========="

rm -rf "${SRC_DIR}"
tar -xzf "${ECCODES_TARBALL}"

if [ ! -f "${SRC_DIR}/CMakeLists.txt" ]; then
  echo "ERROR: unpacked source tree not found:"
  echo "  ${SRC_DIR}"
  echo "Contents of ${ECCODES_SRC}:"
  ls -l "${ECCODES_SRC}"
  exit 1
fi

# ------------------------------------------------------------
# Configure, build, test, install
#
# Out of source build, as the installation instructions require.
# ENABLE_PNG is off by default upstream and is switched on here
# because libpng-dev is installed above.
# ------------------------------------------------------------

echo "========== Configuring ecCodes =========="

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# CMAKE_PREFIX_PATH is what lets find_package( libaec ) pick up the
# libaec installed above when ECCODES_PREFIX is not a default
# system location.
cmake \
  -DCMAKE_INSTALL_PREFIX="${ECCODES_PREFIX}" \
  -DCMAKE_PREFIX_PATH="${ECCODES_PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DENABLE_FORTRAN=ON \
  -DENABLE_NETCDF=ON \
  -DENABLE_JPG=ON \
  -DENABLE_PNG=ON \
  ${ECCODES_AEC_FLAG} \
  "${SRC_DIR}"

echo "========== Building ecCodes =========="

make -j "${ECCODES_JOBS}"

if [ "${ECCODES_RUN_TESTS}" = "1" ]; then
  echo "========== Running the ecCodes test suite =========="
  # Tests are reported but not fatal: a single failing test is not a
  # reason to leave the machine without the ecCodes tools. The summary
  # below states whether they passed.
  if ctest -j "${ECCODES_JOBS}" --output-on-failure; then
    ECCODES_TEST_RESULT="passed"
  else
    ECCODES_TEST_RESULT="FAILED (see the ctest output above)"
  fi
else
  ECCODES_TEST_RESULT="skipped (ECCODES_RUN_TESTS=${ECCODES_RUN_TESTS})"
fi

echo "========== Installing into ${ECCODES_PREFIX} =========="

sudo make install

# Register the new shared libraries. On Ubuntu /usr/local/lib is
# already on the loader path via /etc/ld.so.conf.d/libc.conf.
sudo ldconfig

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

echo "========== Verifying the installation =========="

CODES_INFO="${ECCODES_PREFIX}/bin/codes_info"

if [ ! -x "${CODES_INFO}" ]; then
  echo "ERROR: ${CODES_INFO} was not installed."
  exit 1
fi

"${CODES_INFO}"

echo "============================================================"
echo "ecCodes ${ECCODES_VERSION} installed in ${ECCODES_PREFIX}"
echo "Test suite: ${ECCODES_TEST_RESULT}"
if [ "${ECCODES_WITH_AEC}" = "1" ]; then
  echo "CCSDS/AEC:  enabled (libaec ${LIBAEC_VERSION}, same prefix)"
else
  echo "CCSDS/AEC:  disabled"
fi
echo ""
echo "Tools such as grib_ls, grib_dump and grib_to_netcdf are in"
echo "  ${ECCODES_PREFIX}/bin"
if [ "${ECCODES_PREFIX}" = "/usr/local" ]; then
  echo "which is already on the default PATH."
else
  echo "Add them to your environment with:"
  echo "  export PATH=${ECCODES_PREFIX}/bin:\$PATH"
  echo "  export LD_LIBRARY_PATH=${ECCODES_PREFIX}/lib:\$LD_LIBRARY_PATH"
fi
echo ""
echo "Inspect an ECMWF open data file with, for example:"
echo "  grib_ls ${ARW_ROOT}/BC/*.grib2"
echo ""
echo "Python bindings (optional):"
echo "  export ECCODES_DIR=${ECCODES_PREFIX}"
echo "  pip3 install eccodes --no-binary eccodes"
echo "============================================================"
