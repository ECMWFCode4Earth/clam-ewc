# Sample Run Script

This directory contains a sample run using **ECMWF IFS pre-MTG2 data** as the **initial and boundary conditions**.

## Getting Started

Before running the model, first download the boundary condition files by running:

```bash
bash download_bc.sh
```

This script retrieves the Boundary Condition files from ECMWF test data here:

https://confluence.ecmwf.int/spaces/DAC/pages/228871388/Test+data+for+the+US+Weather+Research+and+Forecasting+WRF+model

## Run the Model

After the boundary condition files have been downloaded:

1. Modify the parameters in `main_wrf.sh` as needed for your run.
2. Start the model with:

```bash
bash main_wrf.sh
```

## Notes

- Make sure the required input files are available before launching the run.
- Review `main_wrf.sh` to confirm paths, configuration, and runtime settings are correct for your environment.
