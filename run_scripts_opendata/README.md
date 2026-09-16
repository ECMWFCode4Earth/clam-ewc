# Sample Run Script (ECMWF open data)

This directory contains a sample run using **ECMWF open data** (IFS operational forecast, 0.25°) as the **initial and boundary conditions**, downloaded from:

https://www.ecmwf.int/en/forecasts/datasets/open-data

## Prerequisites

Two build steps are specific to this case:

1. **WPS with the open data patches** — `build_scripts/03_install_wrf_wps_openData.sh`. It installs the ECMWF version of `ungrib/src/rd_grib2.F` and `Vtable.ECMWF_GRIB2_opendata`, both of which ungrib needs to decode these files.
2. **ecCodes** — `build_scripts/05_install_eccodes.sh`. `download_bc.sh` uses `grib_set` and fails early if it is not on the `PATH`.

## Getting Started

The boundary conditions are downloaded automatically by `main_wrf.sh`, so the usual starting point is:

```bash
ARW_ROOT=/data/ARW ./main_wrf.sh
```

`download_bc.sh` can also be run on its own:

```bash
ARW_ROOT=/data/ARW RUN_DATE=20260916 CYC=00 FLENGTH=6 ./download_bc.sh
```

It downloads one file per 3 hourly forecast step, from the analysis (0h) out to `FLENGTH`, into `$ARW_ROOT/BC`, and repacks each one from `packingType = grid_ccsds` to `grid_simple`, because the GRIB2 decoder in ungrib cannot read CCSDS packing.

Defaults, all overridable from the environment:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RUN_DATE` | today, UTC | forecast date, `YYYYMMDD` |
| `CYC` | `00` | initialisation time |
| `FLENGTH` | `6` | forecast length in hours |
| `STEP_HOURS` | `3` | step between files, matches `interval_seconds` in `namelist.wps.in` |

`RUN_DATE`, `CYC` and `FLENGTH` are the same three variables in `main_wrf.sh`, which passes its values on to `download_bc.sh`.

## Run the Model

Start the model with:

```bash
ARW_ROOT=/data/ARW ./main_wrf.sh
```

`RUN_DATE`, `CYC` and `FLENGTH` default to the current UTC date, `00` and `6` hours. Either edit them at the top of `main_wrf.sh`, or set them for a single run:

```bash
RUN_DATE=20260916 CYC=12 FLENGTH=24 ARW_ROOT=/data/ARW ./main_wrf.sh
```

Review the rest of `main_wrf.sh` and the namelist templates for anything else your run needs, such as the domain in `namelist.wps.in`.

## Run the Model on multiple VMs
Only few changes are required to run wrf model on multiple VMs:
1) In run_real.sh.in one should replace line
```bash
bash run_wrf.sh
```
with
```bash
bash run_wrf_multiVMs.sh
```
2) run_wrf_multiVMs.sh.in is provided in this directory and should be updated before running the model with private IPs of your VMs, line:
```bash
mpirun --host 192.168.2.156:$WRF_NP_HALF,192.168.2.134:$WRF_NP_HALF -np "$WRF_NP" ./wrf.exe
```
This example runs wrf.exe on two VMs with WRF_NP total number of tasks where each VMs runs equal number of tasks.

3) Passwordless SSH: mpirun typically launches remote processes over SSH, so the launching node needs key-based SSH access to the other node(s) without a password prompt.


## Notes

- ECMWF open data only keeps the most recent days, and a cycle is not available until it has been produced. If `download_bc.sh` reports a failed download, check that the requested `RUN_DATE`/`CYC` has been published.
- Disk space: repacking to `grid_simple` roughly doubles the file size, about 300 MB per step for the 0.25° fields. A 6 hour run needs close to 1 GB in `$ARW_ROOT/BC`, and a longer `FLENGTH` scales from there.
- Files already present in `$ARW_ROOT/BC` are not downloaded again, so an interrupted run can simply be repeated.
