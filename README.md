# CLAM WRF/WPS Template for the European Weather Cloud

This repository provides a semi-automated installation workflow for building a reproducible WRF/WPS environment on Ubuntu 24.04 virtual machines, with a primary focus on the European Weather Cloud.

The work is part of the Code for Earth 2026 project **CLAM – Cloud-computing based template for NWP Local Area Model**.

The main goal of this repository is to provide a reusable and documented template that helps users install, configure, compile and test a local-area numerical weather prediction environment with WRF and WPS.

## Target platform

The scripts were developed and tested primarily on:

* European Weather Cloud virtual machines
* Ubuntu 24.04
* Intel oneAPI compiler suite
* WRF 4.8.0
* WPS 4.7.0

The default installation directory is:

```bash
$HOME/ARW
```

If needed, users can install the ARW software stack on another disk or mount point by setting the `ARW_ROOT` environment variable before running the relevant scripts. On EWC it is recommended to set ARW_ROOT to a directory on /data e.g.  ARW_ROOT=/data/ARW 

Example:

```bash
ARW_ROOT=/data/ARW ./build_scripts/02_install_arw_third_party_libs.sh
ARW_ROOT=/data/ARW ./build_scripts/03_install_wrf_wps.sh
```

This is optional. The default location remains `$HOME/ARW`.

## Installation workflow

The installation is split into five main steps:

```bash
chmod +x scripts/*.sh

./build_scripts/00_install_system_packages.sh
./build_scripts/01_install_intel_oneapi.sh
./build_scripts/02_install_arw_third_party_libs.sh
./build_scripts/03_install_wrf_wps.sh
./build_scripts/04_download_wps_geog.sh
```

Each script performs one clearly defined part of the setup.

Step 03 comes in two variants, and exactly one of them is run:

| Initial and boundary conditions | Step 03 |
|---------------------------------|---------|
| plain version, sample dataset | `03_install_wrf_wps.sh` |
| ECMWF open data, GRIB2 | `03_install_wrf_wps_openData.sh` |

If you intend to use **ECMWF open data in GRIB2 format**, replace step 03 with the open data variant and add `05_install_eccodes.sh`. See [Working with ECMWF open data](#working-with-ecmwf-open-data-grib2):

```bash
chmod +x scripts/*.sh

./build_scripts/00_install_system_packages.sh
./build_scripts/01_install_intel_oneapi.sh
./build_scripts/02_install_arw_third_party_libs.sh
./build_scripts/03_install_wrf_wps_openData.sh
./build_scripts/04_download_wps_geog.sh
./build_scripts/05_install_eccodes.sh
```

### Ansible

The same installation is also available as an Ansible playbook in
[`ansible/`](ansible/), for building several VMs from one place or for
re-running a step without having to track what was already done:

```bash
cd ansible
cp inventory/hosts.ini.example inventory/hosts.ini   # then edit it
ansible-playbook site.yml -e arw_root=/data/ARW
ansible-playbook site.yml -e arw_root=/data/ARW -e wps_ecmwf_opendata=true  # ECMWF open data
```

One role per script, with the same build settings and the same
`${ARW_ROOT}/arw_intel_env.sh`, so the `run_scripts` are unaffected by
the choice. See [`ansible/README.md`](ansible/README.md). The shell
scripts remain the reference implementation.

## Script overview

### `00_install_system_packages.sh`

This script prepares a fresh Ubuntu 24.04 system for compiling WRF, WPS and their required dependencies.

The script installs the required Ubuntu packages, including:

* C, C++ and Fortran development tools
* GNU compilers and standard build utilities
* shell tools required by WRF/WPS
* archive and compression utilities
* system development headers
* `wget`, `curl`, `git`, `rsync` and other useful installation tools

This script should be run first on a fresh VM. If you intend to run the model on multiple VMs, this script must be executed on each of them.

### `01_install_intel_oneapi.sh`

This script installs the Intel oneAPI compiler environment used for building the WRF/WPS software stack.

The workflow was tested with the Intel oneAPI Toolkit 2026 offline installer. The installer can either be downloaded by the script or provided manually if it already exists on the system.

A typical offline installer filename is:

```text
intel-oneapi-toolkit-2026.0.0.198_offline.sh
```

If the Intel installer is executed with `sudo`, the system-wide installation path is usually:

```bash
/opt/intel/oneapi
```

If it is executed as a normal user, the user installation path is usually:

```bash
$HOME/intel/oneapi
```

The later scripts detect both common locations automatically by looking for:

```bash
/opt/intel/oneapi/setvars.sh
$HOME/intel/oneapi/setvars.sh
```

After Intel oneAPI is installed, the script verifies that the required compilers and MPI compiler wrappers are available:

```bash
icx
icpx
ifx
mpiicx
mpiicpx
mpiifx
```
If you intend to run the model on multiple VMs, this script must be executed on each of them.

### `02_install_arw_third_party_libs.sh`

This script downloads, builds and installs the third-party libraries required by WRF and WPS. On EWC we recommend running it with:

```bash
ARW_ROOT=/data/ARW ./build_scripts/02_install_arw_third_party_libs.sh
```

The libraries are installed under:

```bash
$ARW_ROOT/LIBRARIES
```

By default this means:

```bash
$HOME/ARW/LIBRARIES
```

The script builds the following packages:

* zlib 1.3.1
* libpng 1.6.43
* JasPer 1.900.1
* HDF5 1.14.6
* netCDF-C 4.9.2
* netCDF-Fortran 4.6.1

JasPer 1.900.1 is installed separately under:

```bash
$ARW_ROOT/JASPER-1.900.1
```

This older JasPer version is used because it provides compatibility with the WPS `ungrib.exe` build requirements.

The script uses Intel compilers and Intel MPI compiler wrappers:

```bash
CC=icx
CXX=icpx
FC=ifx

MPICC=mpiicx
MPICXX=mpiicpx
MPIFC=mpiifx
```

HDF5 and NetCDF are built with parallel support using Intel MPI wrappers.

The script also creates a reusable environment file:

```bash
$ARW_ROOT/arw_intel_env.sh
```

This file can be sourced before compiling or running WRF/WPS:

```bash
source $HOME/ARW/arw_intel_env.sh
```

The environment file defines compiler variables, MPI compiler wrappers, NetCDF/HDF5 paths, JasPer paths, WPS compression variables and WRF runtime settings.
If you intend to run the model on multiple VMs, this script needs to be executed only on one of them and after setting ARW_ROOT to a filesystem mounted on all VMs.

### `03_install_wrf_wps.sh`

This is the plain version of step 03, for the sample dataset. If you are using ECMWF open data in GRIB2 format, run `03_install_wrf_wps_openData.sh` instead, as described in [Working with ECMWF open data](#working-with-ecmwf-open-data-grib2). Everything below applies to both variants.

On EWC we recommend running it with:

```bash
ARW_ROOT=/data/ARW ./build_scripts/03_install_wrf_wps.sh
```

This script configures and compiles WRF 4.8.0 and WPS 4.7.0.

It assumes that the previous third-party library installation step was completed successfully and that the following file exists:

```bash
$HOME/ARW/arw_intel_env.sh
```

The script builds:

* WRF 4.8.0
* WPS 4.7.0

The WRF source code is cloned from the official WRF GitHub repository using:

```bash
git clone --branch v4.8.0 --recursive https://github.com/wrf-model/WRF.git
```

The WPS source code is cloned using:

```bash
git clone --branch v4.7.0 https://github.com/wrf-model/WPS.git
```

For WRF, the script is designed for a distributed-memory build:

```text
Linux x86_64, Intel compiler, dmpar
```

When WRF asks for the nesting option, the expected choice is:

```text
basic
```

After configuration, the script forces Intel MPI compiler wrappers in `configure.wrf`:

```bash
DM_FC = mpiifx
DM_CC = mpiicx
```

This avoids possible cases where generic `mpif90` or `mpicc` wrappers point to GNU backends instead of Intel backends.

The WRF build keeps `-O3` optimization but removes the Intel `-ip` option:

```bash
sed -i 's/ -ip / /g' configure.wrf
```

This choice was made because `-ip` may cause failures during the WRF build on some VM configurations.

The final WRF compilation is performed with:

```bash
./compile -j 1 em_real
```

The script then checks that the main WRF executables were created:

```bash
main/real.exe
main/wrf.exe
```

For WPS, the script uses the serial build configuration:

```text
Linux x86_64, Intel compiler, serial
```

WPS is usually built serial, while WRF itself is built with MPI.

The script modifies `configure.wps` so that it points to the compiled WRF directory and uses JasPer 1.900.1, libpng and zlib for `ungrib.exe` compression support:

```bash
COMPRESSION_LIBS = -L$ARW_ROOT/JASPER-1.900.1/lib -ljasper -L$ARW_ROOT/LIBRARIES/lib -lpng -lz
COMPRESSION_INC  = -I$ARW_ROOT/JASPER-1.900.1/include -I$ARW_ROOT/LIBRARIES/include
```

After compilation, the script verifies that the WPS executables exist:

```bash
geogrid.exe
ungrib.exe
metgrid.exe
```

## Expected result

After all installation scripts complete successfully, the user should have:

```bash
$HOME/ARW/WRF
$HOME/ARW/WPS
$HOME/ARW/LIBRARIES
$HOME/ARW/JASPER-1.900.1
$HOME/ARW/arw_intel_env.sh
```

The main executables should be available as:

```bash
$HOME/ARW/WRF/main/wrf.exe
$HOME/ARW/WRF/main/real.exe

$HOME/ARW/WPS/geogrid.exe
$HOME/ARW/WPS/ungrib.exe
$HOME/ARW/WPS/metgrid.exe
```

Before using the installed environment, source:

```bash
source $HOME/ARW/arw_intel_env.sh
```

If you intend to run the model on multiple VMs, this script needs to be executed only on one of them and after setting ARW_ROOT to a filesystem mounted on all VMs.

### `04_download_wps_geog.sh`
This scrip downloads Mandatory Static Data for WRF model on the highest resolution. It is also possible to get data on lower resolution following instructions from: https://www2.mmm.ucar.edu/wrf/users/download/get_sources_wps_geog.html#mandatory
On EWC we recommend running it with:

```bash
ARW_ROOT=/data/ARW ./build_scripts/04_download_wps_geog.sh
```
If you intend to run the model on multiple VMs, this script needs to be executed only on one of them and after setting ARW_ROOT to a filesystem mounted on all VMs.

### `05_install_eccodes.sh`

This script is **optional**. It is required only if you want to work with **ECMWF open data in GRIB2 format**, because those files are CCSDS packed (`packingType = grid_ccsds`), which the GRIB2 decoder in `ungrib.exe` cannot read. The `download_bc.sh` script in `run_scripts_opendata/` uses the ecCodes `grib_set` tool to repack them to `grid_simple`, and stops with an error if ecCodes is not available.

ecCodes is also the standard toolset for inspecting these files, with `grib_ls`, `grib_dump`, `grib_get` and `grib_to_netcdf`.

The script installs ecCodes centrally, so it needs `sudo`:

```bash
ARW_ROOT=/data/ARW ./build_scripts/05_install_eccodes.sh
```

The default installation prefix is:

```bash
/usr/local
```

which is already on the default `PATH`. `ARW_ROOT` is used only for the download and build directory, under `$ARW_ROOT/src`.

The script installs ecCodes 2.48.0 together with libaec 1.1.4, which provides the CCSDS decompression. libaec is built from source on purpose: ecCodes 2.48.0 requires libaec 1.1.4 or newer, while Ubuntu 24.04 only packages 1.1.2, so the distribution package would leave CCSDS support disabled.

The remaining build dependencies are installed from Ubuntu packages, including `cmake`, which is not part of `00_install_system_packages.sh`.

The version, prefix and build options can be overridden from the environment:

```bash
ECCODES_VERSION=2.48.0
ECCODES_PREFIX=/usr/local
ECCODES_RUN_TESTS=1
ECCODES_WITH_AEC=1
```

Because ecCodes is installed into a system directory rather than into `ARW_ROOT`, this script must be executed on **each VM** that runs `download_bc.sh` or the ecCodes command line tools.

After installation, check the result with:

```bash
codes_info
```

## Working with ECMWF open data (GRIB2)

To run the model with ECMWF open data (IFS operational forecast, 0.25°) instead of the sample dataset, the standard workflow changes in two places:

1. **Replace** step 03: run `03_install_wrf_wps_openData.sh` instead of `03_install_wrf_wps.sh`. The two are alternatives and only one of them is run. The open data variant builds the same WRF 4.8.0 and WPS 4.7.0, and additionally installs the ECMWF version of `WPS/ungrib/src/rd_grib2.F` and the `Vtable.ECMWF_GRIB2_opendata` variable table, both of which `ungrib.exe` needs in order to decode these files.
2. **Add** `05_install_eccodes.sh` for the CCSDS repacking described above.

The matching run scripts are in `run_scripts_opendata/`, which has its own README. They download the boundary conditions automatically from https://data.ecmwf.int, one file per 3 hourly forecast step, and repack each one before `ungrib.exe` reads it.

## Notes on user interaction

The installation is largely automated, the WRF and WPS configuration scripts will automatically select the correct build options interactively.

For WRF, choose:

```text
Linux x86_64, Intel compiler, dmpar
basic nesting
```

For WPS, choose:

```text
Linux x86_64, Intel compiler, serial
```

## Current status

The repository will be extended with:

* benchmark results for different EWC VM configurations
* notes on performance, CPU scaling and I/O quilting

## Disclaimer

This repository is intended as a practical installation and testing template for the CLAM project. It does not replace the official WRF, WPS, Intel oneAPI, HDF5 or NetCDF documentation. Instead, it provides a tested and reproducible starting point for building WRF/WPS on the European Weather Cloud.

