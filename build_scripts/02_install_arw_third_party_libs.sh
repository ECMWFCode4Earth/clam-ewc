#!/bin/bash
set -eo pipefail

# ============================================================
# ARW third-party libraries installation script
#
# This script assumes Intel oneAPI is already installed in:
#   /opt/intel/oneapi
#
# It builds:
#   zlib 1.3.1
#   libpng 1.6.43
#   JasPer 1.900.1
#   HDF5 1.14.6
#   netCDF-C 4.9.2
#   netCDF-Fortran 4.6.1
#
# Installation root:
#   $HOME/ARW
#
# Library prefix:
#   $HOME/ARW/LIBRARIES
#
# JasPer 1.900.1 prefix:
#   $HOME/ARW/JASPER-1.900.1
# ============================================================

export ARW_ROOT="${ARW_ROOT:-${HOME}/ARW}"
export DIR="${ARW_ROOT}/LIBRARIES"
export SRC="${ARW_ROOT}/src"
export TESTS="${ARW_ROOT}/TESTS"
export RUNS="${ARW_ROOT}/RUNS"
export JASPER19001="${ARW_ROOT}/JASPER-1.900.1"

export BUILD_JOBS=4

if [ -f /opt/intel/oneapi/setvars.sh ]; then
  ONEAPI_SETVARS="/opt/intel/oneapi/setvars.sh"
elif [ -f "${HOME}/intel/oneapi/setvars.sh" ]; then
  ONEAPI_SETVARS="${HOME}/intel/oneapi/setvars.sh"
else
  echo "ERROR: Intel oneAPI setvars.sh not found."
  echo "Please install Intel oneAPI before running this script."
  exit 1
fi

echo "Using Intel oneAPI environment:"
echo "  ${ONEAPI_SETVARS}"

set +u
set +e
source "${ONEAPI_SETVARS}" --force
set -e

export CC=icx
export CXX=icpx
export FC=ifx
export F77=ifx
export F90=ifx

export MPICC=mpiicx
export MPICXX=mpiicpx
export MPIFC=mpiifx
export MPIF77=mpiifx
export MPIF90=mpiifx

mkdir -p "${ARW_ROOT}" "${DIR}" "${SRC}" "${TESTS}" "${RUNS}"

export PATH="${JASPER19001}/bin:${DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${JASPER19001}/lib:${DIR}/lib:${DIR}/lib64:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="${JASPER19001}/lib:${DIR}/lib:${DIR}/lib64:${LIBRARY_PATH:-}"
export CPATH="${JASPER19001}/include:${DIR}/include:${CPATH:-}"
export PKG_CONFIG_PATH="${DIR}/lib/pkgconfig:${DIR}/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"

export NETCDF="${DIR}"
export HDF5="${DIR}"

export JASPERLIB="${JASPER19001}/lib"
export JASPERINC="${JASPER19001}/include"

export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export NETCDF_classic=1

export OMP_NUM_THREADS=1
export OMP_STACKSIZE=512M
export KMP_STACKSIZE=512M

ulimit -s unlimited

echo "============================================================"
echo "ARW_ROOT      = ${ARW_ROOT}"
echo "LIBRARIES     = ${DIR}"
echo "SRC           = ${SRC}"
echo "JASPER19001   = ${JASPER19001}"
echo "============================================================"

echo "Checking Intel compilers:"
which icx
which ifx
which mpiicx
which mpiifx

icx --version | head -1
ifx --version | head -1

# ------------------------------------------------------------
# Create reusable environment script
# ------------------------------------------------------------

cat > "${ARW_ROOT}/arw_intel_env.sh" <<EOF
#!/bin/bash

source /opt/intel/oneapi/setvars.sh --force

export ARW_ROOT=${ARW_ROOT}
EOF

cat >> "${ARW_ROOT}/arw_intel_env.sh" <<'EOF'
export DIR=${ARW_ROOT}/LIBRARIES
export SRC=${ARW_ROOT}/src
export TESTS=${ARW_ROOT}/TESTS
export RUNS=${ARW_ROOT}/RUNS

export WRF_DIR=${ARW_ROOT}/WRF
export WPS_DIR=${ARW_ROOT}/WPS
export JASPER19001=${ARW_ROOT}/JASPER-1.900.1

export CC=icx
export CXX=icpx
export FC=ifx
export F77=ifx
export F90=ifx

export MPICC=mpiicx
export MPICXX=mpiicpx
export MPIFC=mpiifx
export MPIF77=mpiifx
export MPIF90=mpiifx

export PATH=${JASPER19001}/bin:${DIR}/bin:${PATH}
export LD_LIBRARY_PATH=${JASPER19001}/lib:${DIR}/lib:${DIR}/lib64:${LD_LIBRARY_PATH}
export LIBRARY_PATH=${JASPER19001}/lib:${DIR}/lib:${DIR}/lib64:${LIBRARY_PATH}
export CPATH=${JASPER19001}/include:${DIR}/include:${CPATH}
export PKG_CONFIG_PATH=${DIR}/lib/pkgconfig:${DIR}/lib64/pkgconfig:${PKG_CONFIG_PATH}

export NETCDF=${DIR}
export HDF5=${DIR}

export JASPERLIB=${JASPER19001}/lib
export JASPERINC=${JASPER19001}/include
export WPS_JASPERLIB=${JASPER19001}/lib
export WPS_JASPERINC=${JASPER19001}/include

export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export NETCDF_classic=1

export OMP_NUM_THREADS=1
export OMP_STACKSIZE=512M
export KMP_STACKSIZE=512M

ulimit -s unlimited
EOF

chmod +x "${ARW_ROOT}/arw_intel_env.sh"

download_with_fallbacks () {
  local output_file="$1"
  shift

  if [ -f "${output_file}" ]; then
    echo "Using existing file: ${output_file}"
    return 0
  fi

  for url in "$@"; do
    echo "Trying download:"
    echo "  ${url}"

    if wget -O "${output_file}.tmp" "${url}"; then
      mv "${output_file}.tmp" "${output_file}"
      echo "Downloaded: ${output_file}"
      return 0
    fi

    rm -f "${output_file}.tmp"
  done

  echo "ERROR: failed to download ${output_file}"
  exit 1
}

check_file_exists () {
  local file="$1"

  if [ ! -f "${file}" ]; then
    echo "ERROR: expected file not found:"
    echo "  ${file}"
    exit 1
  fi
}

# ------------------------------------------------------------
# zlib
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${DIR}/lib/libz.so" ]; then
  echo "========== Building zlib =========="

  download_with_fallbacks \
    "zlib-1.3.1.tar.gz" \
    "https://zlib.net/fossils/zlib-1.3.1.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz"

  rm -rf zlib-1.3.1
  tar -xzf zlib-1.3.1.tar.gz

  cd zlib-1.3.1

  CC=icx ./configure --prefix="${DIR}"

  make -j "${BUILD_JOBS}"
  make install

  cd "${SRC}"
else
  echo "zlib already installed."
fi

check_file_exists "${DIR}/lib/libz.so"
check_file_exists "${DIR}/include/zlib.h"

echo "zlib check:"
ldd "${DIR}/lib/libz.so" | grep -E "imf|svml|libc|libm" || true

# ------------------------------------------------------------
# libpng
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${DIR}/lib/libpng16.so" ]; then
  echo "========== Building libpng =========="

  download_with_fallbacks \
    "libpng-1.6.43.tar.gz" \
    "https://download.sourceforge.net/libpng/libpng-1.6.43.tar.gz" \
    "https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.43.tar.gz"

  rm -rf libpng-1.6.43 libpng-1.6.43.tar
  tar -xzf libpng-1.6.43.tar.gz

  if [ -d libpng-1.6.43 ]; then
    cd libpng-1.6.43
  elif [ -d libpng-1.6.43.tar ]; then
    cd libpng-1.6.43.tar
  else
    echo "ERROR: libpng source directory not found after extraction."
    exit 1
  fi

  CC=icx \
  CPPFLAGS="-I${DIR}/include" \
  LDFLAGS="-L${DIR}/lib" \
  ./configure --prefix="${DIR}"

  make -j "${BUILD_JOBS}"
  make install

  cd "${SRC}"
else
  echo "libpng already installed."
fi

check_file_exists "${DIR}/lib/libpng16.so"
check_file_exists "${DIR}/include/png.h"

echo "libpng check:"
ldd "${DIR}/lib/libpng.so" | grep -E "z|imf|svml" || true

# ------------------------------------------------------------
# JasPer 1.900.1
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${JASPER19001}/lib/libjasper.so.1" ]; then
  echo "========== Building JasPer 1.900.1 =========="

  download_with_fallbacks \
    "jasper-1.900.1.zip" \
    "https://www.ece.uvic.ca/~frodo/jasper/software/jasper-1.900.1.zip" \
    "https://src.fedoraproject.org/repo/pkgs/jasper/jasper-1.900.1.zip/6b905a9c2aca2e275544212666eefc4c/jasper-1.900.1.zip"

  rm -rf jasper-1.900.1
  unzip -q jasper-1.900.1.zip

  cd jasper-1.900.1

  CC=icx \
  CFLAGS="-O1 -fPIC -std=gnu89 \
  -Wno-implicit-function-declaration \
  -Wno-incompatible-function-pointer-types \
  -Wno-incompatible-pointer-types \
  -Wno-error=incompatible-function-pointer-types \
  -Wno-error=incompatible-pointer-types \
  -I${DIR}/include" \
  LDFLAGS="-L${DIR}/lib" \
  ./configure \
    --prefix="${JASPER19001}" \
    --enable-shared

  make -j 1
  make install

  cd "${SRC}"
else
  echo "JasPer 1.900.1 already installed."
fi

check_file_exists "${JASPER19001}/lib/libjasper.so.1"

echo "Checking JasPer symbol jpc_decode:"
nm -D "${JASPER19001}/lib/libjasper.so" | grep jpc_decode

# ------------------------------------------------------------
# HDF5
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${DIR}/lib/libhdf5.so" ]; then
  echo "========== Building HDF5 =========="

  download_with_fallbacks \
    "hdf5-1.14.6.tar.gz" \
    "https://support.hdfgroup.org/releases/hdf5/v1_14/v1_14_6/downloads/hdf5-1.14.6.tar.gz" \
    "https://github.com/HDFGroup/hdf5/releases/download/hdf5_1.14.6/hdf5-1.14.6.tar.gz"

  rm -rf hdf5-1.14.6
  tar -xzf hdf5-1.14.6.tar.gz

  cd hdf5-1.14.6

  CC=mpiicx FC=mpiifx \
  CFLAGS="-O2 -fPIC" \
  FCFLAGS="-O2 -fPIC" \
  CPPFLAGS="-I${DIR}/include" \
  LDFLAGS="-L${DIR}/lib" \
  ./configure \
    --prefix="${DIR}" \
    --enable-fortran \
    --enable-parallel \
    --enable-shared \
    --enable-hl \
    --with-zlib="${DIR}"

  make -j "${BUILD_JOBS}"
  make install

  cd "${SRC}"
else
  echo "HDF5 already installed."
fi

check_file_exists "${DIR}/lib/libhdf5.so"
check_file_exists "${DIR}/lib/libhdf5_fortran.so"

echo "HDF5 check:"
ldd "${DIR}/lib/libhdf5.so" | grep -E "z|mpi|imf|svml" || true

# ------------------------------------------------------------
# netCDF-C
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${DIR}/lib/libnetcdf.so" ]; then
  echo "========== Building netCDF-C =========="

  download_with_fallbacks \
    "netcdf-c-4.9.2.tar.gz" \
    "https://github.com/Unidata/netcdf-c/archive/refs/tags/v4.9.2.tar.gz"

  rm -rf netcdf-c-4.9.2
  tar -xzf netcdf-c-4.9.2.tar.gz

  cd netcdf-c-4.9.2

  CC=mpiicx \
  CPPFLAGS="-I${DIR}/include" \
  LDFLAGS="-L${DIR}/lib" \
  LIBS="-lhdf5_hl -lhdf5 -lz" \
  ./configure \
    --prefix="${DIR}" \
    --enable-netcdf-4 \
    --enable-shared \
    --disable-dap \
    --disable-libxml2 \
    --disable-byterange

  make -j "${BUILD_JOBS}"
  make install

  cd "${SRC}"
else
  echo "netCDF-C already installed."
fi

check_file_exists "${DIR}/lib/libnetcdf.so"

echo "netCDF-C check:"
"${DIR}/bin/nc-config" --prefix
"${DIR}/bin/nc-config" --has-nc4
"${DIR}/bin/nc-config" --has-hdf5
ldd "${DIR}/lib/libnetcdf.so" | grep -E "hdf5|z|mpi|imf|svml" || true

# ------------------------------------------------------------
# netCDF-Fortran
# ------------------------------------------------------------

cd "${SRC}"

if [ ! -f "${DIR}/lib/libnetcdff.so" ]; then
  echo "========== Building netCDF-Fortran =========="

  download_with_fallbacks \
    "netcdf-fortran-4.6.1.tar.gz" \
    "https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v4.6.1.tar.gz"

  rm -rf netcdf-fortran-4.6.1
  tar -xzf netcdf-fortran-4.6.1.tar.gz

  cd netcdf-fortran-4.6.1

  FC=mpiifx \
  F77=mpiifx \
  CPPFLAGS="-I${DIR}/include" \
  LDFLAGS="-L${DIR}/lib" \
  LIBS="-lnetcdf -lhdf5_hl -lhdf5 -lz" \
  ./configure \
    --prefix="${DIR}" \
    --enable-shared

  make -j "${BUILD_JOBS}"
  make install

  cd "${SRC}"
else
  echo "netCDF-Fortran already installed."
fi

check_file_exists "${DIR}/lib/libnetcdff.so"

echo "netCDF-Fortran check:"
"${DIR}/bin/nf-config" --prefix
ldd "${DIR}/lib/libnetcdff.so" | grep -E "netcdf|hdf5|z|mpi|imf|svml" || true

echo
echo "============================================================"
echo "Third-party libraries installed successfully."
echo
echo "Environment file:"
echo "  ${ARW_ROOT}/arw_intel_env.sh"
echo
echo "To load the environment:"
echo "  source ${ARW_ROOT}/arw_intel_env.sh"
echo "============================================================"
