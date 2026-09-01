# Sample Run Script

This directory contains a sample run using **ECMWF IFS pre-MTG2 data** as the **initial and boundary conditions**.

## Getting Started

Before running the model, first download the boundary condition files by running:

```bash
ARW_ROOT=/data/ARW ./download_bc.sh
```

This script retrieves the Boundary Condition files from ECMWF test data here:

https://confluence.ecmwf.int/spaces/DAC/pages/228871388/Test+data+for+the+US+Weather+Research+and+Forecasting+WRF+model

## Run the Model

After the boundary condition files have been downloaded:

1. Modify the parameters in `main_wrf.sh` as needed for your run.
2. Start the model with:

```bash
ARW_ROOT=/data/ARW ./main_wrf.sh
```

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
2) run_wrf_multiVMs.sh.in is provided in the run_scripts directory and should be updated before running the model with private IPs of your VMs, line:
```bash
mpirun --host 192.168.2.156:$WRF_NP_HALF,192.168.2.134:$WRF_NP_HALF -np "$WRF_NP" ./wrf.exe
```
This example runs wrf.exe on two VMs with WRF_NP total number of tasks where each VMs runs equal number of tasks.

3) Passwordless SSH: mpirun typically launches remote processes over SSH, so the launching node needs key-based SSH access to the other node(s) without a password prompt.


## Notes

- Make sure the required input files are available before launching the run.
- Review `main_wrf.sh` to confirm paths, configuration, and runtime settings are correct for your environment.
