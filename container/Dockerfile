# syntax=docker/dockerfile:1

# =============================================================================
# Multi-stage build for the CLAM WRF 4.8.0 / WPS 4.7.0 stack.
#
#   builder  : full Intel oneAPI (compilers + MPI) + all third-party libs +
#              compiled WRF/WPS. Reuses the repository build_scripts unchanged.
#   runtime  : slim image with only the Intel oneAPI *runtime* redistributables
#              (no compilers) plus the compiled binaries/libraries copied from
#              the builder. Designed to run rootless under Apptainer.
#
# Build from the repository root (the directory containing build_scripts/):
#   docker build -f container/Dockerfile -t clam-wrf:latest .
# =============================================================================

# Intel oneAPI release used for BOTH stages. Keep the builder compilers and the
# runtime redistributables on the same release to avoid Fortran/MPI symbol
# mismatches. Pin to an exact version (e.g. 2026.0.0) for reproducible builds.
ARG ONEAPI_CHANNEL=all

# Build the ECMWF open-data WPS variant when set to 1. It is a superset of the
# plain build: same WRF/WPS, plus the ECMWF ungrib patches (rd_grib2.F +
# Vtable.ECMWF_GRIB2_opendata) needed to decode the open-data GRIB2 files.
# Left at 0 by default to keep the shipped ungrib behaviour unchanged.
ARG WRF_OPENDATA=0

# -----------------------------------------------------------------------------
# Stage 1: builder
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# System build packages (mirrors 00_install_system_packages.sh, minus sudo).
# apt-get upgrade pulls the latest security-patched base packages.
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
      build-essential gcc g++ gfortran make m4 perl csh tcsh file \
      wget curl tar gzip bzip2 xz-utils patch pkg-config \
      libc6-dev linux-libc-dev unzip git ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# Intel oneAPI APT repository + compilers and Intel MPI (replaces the offline
# installer used by 01_install_intel_oneapi.sh). Installs setvars.sh under
# /opt/intel/oneapi, which the build_scripts detect automatically.
RUN wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
      | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
      > /etc/apt/sources.list.d/oneAPI.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      intel-oneapi-compiler-dpcpp-cpp \
      intel-oneapi-compiler-fortran \
      intel-oneapi-mpi-devel \
    && rm -rf /var/lib/apt/lists/*

# Fixed prefix so the image does not depend on any user's $HOME.
ENV ARW_ROOT=/opt/arw

# Build third-party libs then WRF/WPS using the repository scripts as-is.
# WRF_OPENDATA=1 selects 03_install_wrf_wps_openData.sh (adds the ECMWF
# open-data ungrib patches); otherwise the plain 03_install_wrf_wps.sh is used.
ARG WRF_OPENDATA
COPY build_scripts/02_install_arw_third_party_libs.sh \
     build_scripts/03_install_wrf_wps.sh \
     build_scripts/03_install_wrf_wps_openData.sh \
     /tmp/build_scripts/
RUN chmod +x /tmp/build_scripts/*.sh \
    && /tmp/build_scripts/02_install_arw_third_party_libs.sh \
    && if [ "${WRF_OPENDATA:-0}" = "1" ]; then \
         echo "==> Building WPS with ECMWF open-data patches"; \
         /tmp/build_scripts/03_install_wrf_wps_openData.sh; \
       else \
         /tmp/build_scripts/03_install_wrf_wps.sh; \
       fi

# -----------------------------------------------------------------------------
# Stage 2: runtime (slim)
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS runtime

# Explicit PATH so `ls` and the model binaries resolve regardless of how the
# SIF is launched (Apptainer/MPI can otherwise pass through an empty PATH).
ENV DEBIAN_FRONTEND=noninteractive \
    ARW_ROOT=/opt/arw \
    PATH=/opt/arw/WRF/main:/opt/arw/WPS:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OMP_NUM_THREADS=1 \
    OMP_STACKSIZE=512M \
    KMP_STACKSIZE=512M \
    I_MPI_HYDRA_BOOTSTRAP=ssh

# Minimal runtime packages:
#   tcsh/csh       -> WPS link_grib.csh
#   perl           -> WRF/WPS helper scripts
#   openssh-client -> Intel MPI (Hydra) ssh bootstrap for multi-node runs
#   curl/wget      -> boundary-condition downloads (download_bc.sh)
#   libeccodes-tools -> grib_set/grib_get, used by the open-data download_bc.sh
#                       to repack CCSDS GRIB2 to grid_simple for ungrib
# apt-get upgrade pulls the latest security-patched base packages into the
# runtime image (addresses base-image CVEs flagged by image scanners).
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
      tcsh csh perl openssh-client ca-certificates gnupg wget curl \
      libeccodes-tools libgomp1 procps hostname \
    && rm -rf /var/lib/apt/lists/*

# Intel oneAPI apt repository, kept in its own small layer so the large Intel
# package installs below each land in a separate, independently-pushable layer.
RUN wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
      | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
      > /etc/apt/sources.list.d/oneAPI.list

# Intel oneAPI compiler + Fortran + OpenMP runtime redistributables. Split from
# the MPI install below so the ~1.8 GB of Intel runtime is spread across several
# smaller layers instead of one, which pushes/pulls far better over a registry.
RUN apt-get update && apt-get install -y --no-install-recommends \
      intel-oneapi-runtime-libs \
      intel-oneapi-runtime-fortran \
      intel-oneapi-runtime-openmp \
    && rm -rf /var/lib/apt/lists/*

# Intel MPI runtime in its own layer. intel-oneapi-mpi (not
# intel-oneapi-runtime-mpi) is required because only it ships the mpirun /
# mpiexec.hydra launchers, not just the MPI libraries. Same repo/release as the
# builder so runtimes match.
RUN apt-get update && apt-get install -y --no-install-recommends \
      intel-oneapi-mpi \
    && rm -rf /var/lib/apt/lists/*

# Drop non-runtime Intel artefacts that are not needed to execute the model
# (debug MPI libs, benchmarks, examples, docs/man). Guarded so a layout change
# in a future oneAPI release cannot break the build.
RUN set -eux; \
    rm -rf /opt/intel/oneapi/mpi/*/lib/debug \
           /opt/intel/oneapi/mpi/*/lib/debug_mt \
           /opt/intel/oneapi/mpi/*/benchmarks \
           /opt/intel/oneapi/mpi/*/examples \
           /opt/intel/oneapi/mpi/*/etc/tune* \
           /opt/intel/oneapi/*/share/doc \
           /opt/intel/oneapi/*/share/man \
           /opt/intel/oneapi/*/documentation \
           /opt/intel/oneapi/conda_channel \
      2>/dev/null || true

# Compiled artifacts from the builder (executables, runtime data, shared libs).
COPY --from=builder /opt/arw/WRF/main            /opt/arw/WRF/main
COPY --from=builder /opt/arw/WRF/run             /opt/arw/WRF/run
COPY --from=builder /opt/arw/WPS                 /opt/arw/WPS
COPY --from=builder /opt/arw/LIBRARIES/lib       /opt/arw/LIBRARIES/lib
COPY --from=builder /opt/arw/JASPER-1.900.1/lib  /opt/arw/JASPER-1.900.1/lib

# Slim runtime environment, named so the run_scripts' `$ARW_ROOT/arw_intel_env.sh`
# keeps working without the full oneAPI setvars.sh / compilers.
COPY container/arw_runtime_env.sh /opt/arw/arw_intel_env.sh

# Bundle the run scripts so no host bind is needed to drive a run. All three
# variants are included; run_apptainer.sh's RUN_VARIANT picks which one runs:
#   run_scripts          -> plain sample dataset (default)
#   run_scripts_large     -> larger domain, same sample dataset
#   run_scripts_opendata  -> ECMWF open data (needs the WRF_OPENDATA=1 build)
COPY run_scripts          /opt/arw/run_scripts
COPY run_scripts_large    /opt/arw/run_scripts_large
COPY run_scripts_opendata /opt/arw/run_scripts_opendata

# Symlink the mutable dirs under $ARW_ROOT to the /data bind mount so a single
# `--bind $DATA_DIR:/data` is enough and the run_scripts (which use
# $ARW_ROOT/{GEOG,BC,RUNS}) work unchanged inside the read-only container.
RUN mkdir -p /data \
    && ln -s /data/GEOG /opt/arw/GEOG \
    && ln -s /data/BC   /opt/arw/BC \
    && ln -s /data/RUNS /opt/arw/RUNS
WORKDIR /data

CMD ["/bin/bash"]
