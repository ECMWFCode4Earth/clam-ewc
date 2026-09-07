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
#   docker build -f docker/Dockerfile -t clam-wrf:latest .
# =============================================================================

# Intel oneAPI release used for BOTH stages. Keep the builder compilers and the
# runtime redistributables on the same release to avoid Fortran/MPI symbol
# mismatches. Pin to an exact version (e.g. 2026.0.0) for reproducible builds.
ARG ONEAPI_CHANNEL=all

# -----------------------------------------------------------------------------
# Stage 1: builder
# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# System build packages (mirrors 00_install_system_packages.sh, minus sudo).
RUN apt-get update && apt-get install -y --no-install-recommends \
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
COPY build_scripts/02_install_arw_third_party_libs.sh \
     build_scripts/03_install_wrf_wps.sh \
     /tmp/build_scripts/
RUN chmod +x /tmp/build_scripts/*.sh \
    && /tmp/build_scripts/02_install_arw_third_party_libs.sh \
    && /tmp/build_scripts/03_install_wrf_wps.sh

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
#   tcsh/csh  -> WPS link_grib.csh
#   perl      -> WRF/WPS helper scripts
#   openssh-client -> Intel MPI (Hydra) ssh bootstrap for multi-node runs
RUN apt-get update && apt-get install -y --no-install-recommends \
      tcsh csh perl openssh-client ca-certificates gnupg wget \
      libgomp1 procps hostname \
    && rm -rf /var/lib/apt/lists/*

# Intel oneAPI runtime redistributables (compiler + Fortran + OpenMP) plus the
# full Intel MPI runtime. intel-oneapi-mpi (not intel-oneapi-runtime-mpi) is
# required because only it ships the mpirun / mpiexec.hydra launchers, not just
# the MPI libraries. Same repo/release as the builder so runtimes match.
RUN wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
      | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
      > /etc/apt/sources.list.d/oneAPI.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      intel-oneapi-runtime-libs \
      intel-oneapi-runtime-fortran \
      intel-oneapi-runtime-openmp \
      intel-oneapi-mpi \
    && rm -rf /var/lib/apt/lists/*

# Compiled artifacts from the builder (executables, runtime data, shared libs).
COPY --from=builder /opt/arw/WRF/main            /opt/arw/WRF/main
COPY --from=builder /opt/arw/WRF/run             /opt/arw/WRF/run
COPY --from=builder /opt/arw/WPS                 /opt/arw/WPS
COPY --from=builder /opt/arw/LIBRARIES/lib       /opt/arw/LIBRARIES/lib
COPY --from=builder /opt/arw/JASPER-1.900.1/lib  /opt/arw/JASPER-1.900.1/lib

# Slim runtime environment, named so the run_scripts' `$ARW_ROOT/arw_intel_env.sh`
# keeps working without the full oneAPI setvars.sh / compilers.
COPY docker/arw_runtime_env.sh /opt/arw/arw_intel_env.sh

# Bundle the run scripts so no host bind is needed to drive a run.
COPY run_scripts /opt/arw/run_scripts

# Symlink the mutable dirs under $ARW_ROOT to the /data bind mount so a single
# `--bind $DATA_DIR:/data` is enough and the run_scripts (which use
# $ARW_ROOT/{GEOG,BC,RUNS}) work unchanged inside the read-only container.
RUN mkdir -p /data \
    && ln -s /data/GEOG /opt/arw/GEOG \
    && ln -s /data/BC   /opt/arw/BC \
    && ln -s /data/RUNS /opt/arw/RUNS
WORKDIR /data

CMD ["/bin/bash"]
