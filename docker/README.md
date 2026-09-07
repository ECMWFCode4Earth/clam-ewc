# CLAM WRF/WPS container (Docker → Apptainer)

This folder builds the CLAM **WRF 4.8.0 / WPS 4.7.0** stack as a multi-stage
Docker image and converts it to an **Apptainer** SIF that runs **rootless** on
the EWC virtual machines and on HPC. The compiled binaries are baked into the
image, so no recompilation is needed at run time.

## Contents

| File | Purpose |
|------|---------|
| [`Dockerfile`](Dockerfile) | Multi-stage build: `builder` (full Intel oneAPI + libs + WRF/WPS) and `runtime` (slim, runtime redistributables only). |
| [`arw_runtime_env.sh`](arw_runtime_env.sh) | Slim runtime environment installed as `/opt/arw/arw_intel_env.sh`. |
| [`build_sif.sh`](build_sif.sh) | Builds the image and converts it to a SIF. |
| [`run_apptainer.sh`](run_apptainer.sh) | Rootless launcher that bind-mounts host data into the container. |
| [`install_apptainer.sh`](install_apptainer.sh) | Installs Apptainer on Ubuntu 24.04 or Rocky/RHEL 9. |

## How it works

- **builder stage** — installs the system packages, adds the Intel oneAPI APT
  repository (compilers + Intel MPI), then runs the repository build scripts
  unchanged with `ARW_ROOT=/opt/arw`:
  - `build_scripts/02_install_arw_third_party_libs.sh` (zlib, libpng,
    JasPer 1.900.1, HDF5, netCDF-C, netCDF-Fortran)
  - `build_scripts/03_install_wrf_wps.sh` (WRF dmpar + WPS serial)
- **runtime stage** — installs only the Intel oneAPI **runtime redistributables**
  (`intel-oneapi-runtime-*`, no compilers) and copies the compiled executables,
  runtime data and shared libraries from the builder. `openssh-client` is
  included for Intel MPI's multi-node SSH bootstrap.

Fixed install prefix `/opt/arw` (not `$HOME`) so the image works under any
Apptainer user. Large static data (GEOG, boundary conditions, run output) is
**bind-mounted at run time**, not baked into the image.

## Prerequisites

- Docker (or a compatible daemon) **and** Apptainer on the build host.
- Network access during the build (Intel APT repo + WRF/WPS/library sources).
- Apptainer on every node where the container will run.

Install Apptainer on Ubuntu 24.04 or Rocky/RHEL 9 with the helper script:

```bash
./docker/install_apptainer.sh
```

## 1. Build the image and SIF

Run from the **repository root** (the directory containing `build_scripts/`):

```bash
./docker/build_sif.sh
```

This produces `clam-wrf.sif`. Override names if needed:

```bash
IMAGE=clam-wrf:2026.0 SIF=clam-wrf-2026.0.sif ./docker/build_sif.sh
```

To build only the Docker image (no SIF):

```bash
docker build -f docker/Dockerfile -t clam-wrf:latest .
```

## 2. Prepare the host data directory

The container filesystem is read-only; all writable state lives on a
bind-mounted host directory (`DATA_DIR`), exposed as `/data`:

```text
$DATA_DIR/GEOG   # WPS_GEOG static data (from build_scripts/04_download_wps_geog.sh)
$DATA_DIR/BC     # boundary-condition GRIB files
$DATA_DIR/RUNS   # run directories / model output (writable)
```

```bash
export DATA_DIR=/data/clam        # host path, adjust as needed
mkdir -p "$DATA_DIR"/{GEOG,BC,RUNS}
```

## 3. Runtime test

### 3a. Smoke test — binaries and libraries resolve

```bash
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh bash -c '
  ldd /opt/arw/WRF/main/wrf.exe | grep -E "not found" && echo "MISSING LIBS" || echo "wrf.exe OK"
  ldd /opt/arw/WPS/ungrib.exe   | grep -E "not found" && echo "MISSING LIBS" || echo "ungrib.exe OK"
  which mpirun && mpirun --version | head -1
'
```

Expected: `wrf.exe OK`, `ungrib.exe OK`, and an Intel MPI `mpirun` version line.
Any `not found` line means a runtime library is missing (see Troubleshooting).

### 3b. Single-node end-to-end run

The binaries are at `/opt/arw/WRF/main` and `/opt/arw/WPS`; the launcher adds
both to `PATH` and sources the runtime environment automatically.

```bash
# Interactive shell inside the container
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh bash

# From a prepared run directory on the host (bound under /data/RUNS/<cycle>):
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh bash -c '
  cd /data/RUNS/<cycle>
  ungrib.exe && geogrid.exe && metgrid.exe
  mpirun -np 4  real.exe
  mpirun -np 16 wrf.exe
'
```

Success is `wrfout_d01_*` files in the run directory and `SUCCESS COMPLETE WRF`
in `rsl.out.0000`.

> The repository `run_scripts/*.sh` still work inside the container: they source
> `$ARW_ROOT/arw_intel_env.sh` (provided by the image) and call `mpirun`.

## 4. Multi-node runs (EWC VMs / HPC)

The image bundles Intel MPI and uses SSH for multi-node launch. The same SIF
must exist at the same path on every node, with passwordless SSH between nodes.

```bash
cat > hosts <<'EOF'
192.168.2.156:16
192.168.2.134:16
EOF

export I_MPI_HYDRA_BOOTSTRAP=ssh
export I_MPI_HYDRA_BOOTSTRAP_EXEC=apptainer
export I_MPI_HYDRA_BOOTSTRAP_EXEC_EXTRA_ARGS="exec --bind ${DATA_DIR}:/data ${SIF}"

apptainer exec --bind "${DATA_DIR}:/data" "${SIF}" bash -c '
  source /opt/arw/arw_intel_env.sh
  cd /data/RUNS/<cycle>
  mpirun -f hosts -np 32 /opt/arw/WRF/main/wrf.exe'
```

On a Slurm HPC, let the scheduler place ranks and launch one container per task
(requires the host PMI library bound in and `I_MPI_PMI_LIBRARY` set):

```bash
srun --mpi=pmi2 apptainer exec --bind /data:/data clam-wrf.sif \
  bash -c 'source /opt/arw/arw_intel_env.sh && exec /opt/arw/WRF/main/wrf.exe'
```

See the commented section at the bottom of [`run_apptainer.sh`](run_apptainer.sh)
for details.

## Troubleshooting

- **`... not found` in `ldd`** — the Intel runtime version must match the
  builder compilers. Pin the same oneAPI release in both stages of the
  `Dockerfile` (build arg / package versions) and rebuild.
- **`ulimit -s unlimited` denied** — rootless Apptainer may cap the stack size.
  Raise the host limit (`/etc/security/limits.conf`) or run with a scheduler
  that grants it; WRF needs a large/unlimited stack.
- **Multi-node hangs at startup** — check passwordless SSH between nodes and
  that the SIF path and `--bind` are identical on every node.
- **Reproducible builds** — pin the Intel oneAPI package versions in the
  `Dockerfile` (e.g. `intel-oneapi-compiler-fortran=<version>`); the default
  installs the latest available in the repo.
