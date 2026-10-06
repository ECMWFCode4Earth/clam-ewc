#!/bin/bash
# Runtime environment for the slim WRF/WPS Apptainer image.
# Uses the Intel oneAPI *runtime* redistributables only (no compilers, no full
# setvars.sh). Sourced by the run_scripts as "$ARW_ROOT/arw_intel_env.sh".

export ARW_ROOT="${ARW_ROOT:-/opt/arw}"

# Intel oneAPI runtime (compiler + MPI redistributables). Prefer setvars.sh when
# present, otherwise source the per-component env scripts shipped by the runtime
# packages. Never abort the caller if these are missing.
if [ -f /opt/intel/oneapi/setvars.sh ]; then
  . /opt/intel/oneapi/setvars.sh --force >/dev/null 2>&1 || true
else
  [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && \
    . /opt/intel/oneapi/compiler/latest/env/vars.sh >/dev/null 2>&1 || true
  [ -f /opt/intel/oneapi/mpi/latest/env/vars.sh ] && \
    . /opt/intel/oneapi/mpi/latest/env/vars.sh >/dev/null 2>&1 || true
fi

export DIR="${ARW_ROOT}/LIBRARIES"
export WRF_DIR="${ARW_ROOT}/WRF"
export WPS_DIR="${ARW_ROOT}/WPS"
export JASPER19001="${ARW_ROOT}/JASPER-1.900.1"

export PATH="${JASPER19001}/bin:${DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${JASPER19001}/lib:${DIR}/lib:${DIR}/lib64:${LD_LIBRARY_PATH:-}"

export NETCDF="${DIR}"
export HDF5="${DIR}"
export JASPERLIB="${JASPER19001}/lib"
export JASPERINC="${JASPER19001}/include"
export WPS_JASPERLIB="${JASPER19001}/lib"
export WPS_JASPERINC="${JASPER19001}/include"

export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export NETCDF_classic=1

export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export OMP_STACKSIZE="${OMP_STACKSIZE:-512M}"
export KMP_STACKSIZE="${KMP_STACKSIZE:-512M}"

# May be denied under rootless Apptainer; harmless if it fails.
ulimit -s unlimited 2>/dev/null || true
