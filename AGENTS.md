# AGENTS.md — CLAM WRF/WPS template

Guidance for AI agents working in this repository. Part of Code for Earth 2026
project **CLAM – Cloud-computing based template for NWP Local Area Model**.

## What this repo is

A semi-automated workflow to build and run a reproducible **WRF 4.8.0 / WPS 4.7.0**
environment on Ubuntu 24.04, targeting the **European Weather Cloud (EWC)** VMs
and HPC. Built with the **Intel oneAPI** compilers (`icx`/`icpx`/`ifx`) and
**Intel MPI** (`mpiicx`/`mpiicpx`/`mpiifx`).

## Layout

- `build_scripts/` — ordered install steps (`00`→`04`), run once on a fresh VM.
- `run_scripts/` — templated (`*.in`) job scripts; `main_wrf.sh` orchestrates a run.
- `container/` — multi-stage Docker → Apptainer image that bakes in the compiled
  binaries so **no recompilation** is needed. See `container/README.md`.

## Key conventions

- **Install prefix** is `ARW_ROOT`, default `$HOME/ARW`. On EWC use `/data/ARW`
  (a disk/mount shared across VMs). The Docker image uses a fixed `/opt/arw`.
- Every environment is loaded by sourcing `$ARW_ROOT/arw_intel_env.sh` (compiler,
  MPI, netCDF/HDF5, JasPer paths, WRF runtime vars). Do not re-derive these by hand.
- WRF is built **dmpar** (Intel MPI), `-O3` without `-ip`, compiled `-j 1`.
- WPS is built **serial**, using **JasPer 1.900.1** (separate prefix
  `$ARW_ROOT/JASPER-1.900.1`) for `ungrib.exe`.
- Third-party libs (zlib, libpng, JasPer, HDF5 parallel, netCDF-C/Fortran) live
  under `$ARW_ROOT/LIBRARIES`.

## Build (bare VM)

```bash
./build_scripts/00_install_system_packages.sh          # needs sudo
./build_scripts/01_install_intel_oneapi.sh             # needs sudo (or ONEAPI_USER_INSTALL=1)
ARW_ROOT=/data/ARW ./build_scripts/02_install_arw_third_party_libs.sh
ARW_ROOT=/data/ARW ./build_scripts/03_install_wrf_wps.sh
ARW_ROOT=/data/ARW ./build_scripts/04_download_wps_geog.sh
```

The `02`/`03` scripts are prefix-agnostic (honor `ARW_ROOT`, use no `sudo`) and
must stay that way — the Docker builder reuses them unchanged.

## Container (preferred for reproducible runs)

Prefer the prebuilt image over recompiling. From the repo root:

```bash
./container/build_sif.sh                               # docker build → clam-wrf.sif
DATA_DIR=/data/clam ./container/run_apptainer.sh bash  # rootless Apptainer
```

Runtime data (GEOG, BC, RUNS) is **bind-mounted** at `/data`, never baked in.
Multi-node uses the container's Intel MPI over SSH (see `container/run_apptainer.sh`).

## Run a forecast

`run_scripts/main_wrf.sh` fills the `*.in` templates into `$ARW_ROOT/RUNS/<cycle>`
and drives WPS → real → wrf. Boundary conditions come from `download_bc.sh`.

## Guidance for changes

- Keep `build_scripts/02` and `03` prefix-agnostic and `sudo`-free (Docker relies
  on this). System-package/oneAPI install differences belong in the `Dockerfile`,
  not in `02`/`03`.
- Keep the builder compilers and the runtime redistributables on the **same**
  Intel oneAPI release to avoid Fortran/MPI symbol mismatches.
- Don't bake large static data (GEOG/BC) into the image; bind-mount it.
- WRF needs a large/unlimited stack (`ulimit -s unlimited`); preserve the
  `OMP_STACKSIZE`/`KMP_STACKSIZE` settings in run scripts and env files.
- Do not commit build artifacts, `*.sif`, or `$ARW_ROOT` contents.
