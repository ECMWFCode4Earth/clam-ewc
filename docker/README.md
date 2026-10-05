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
| [`install_docker.sh`](install_docker.sh) | Installs Docker Engine on Ubuntu 24.04 or Rocky/RHEL 9. |
| [`install_apptainer.sh`](install_apptainer.sh) | Installs Apptainer on Ubuntu 24.04 or Rocky/RHEL 9. |

## How it works

- **builder stage** — installs the system packages, adds the Intel oneAPI APT
  repository (compilers + Intel MPI), then runs the repository build scripts
  unchanged with `ARW_ROOT=/opt/arw`:
  - `build_scripts/02_install_arw_third_party_libs.sh` (zlib, libpng,
    JasPer 1.900.1, HDF5, netCDF-C, netCDF-Fortran)
  - `build_scripts/03_install_wrf_wps.sh` (WRF dmpar + WPS serial), **or**
    `build_scripts/03_install_wrf_wps_openData.sh` when built with
    `--build-arg WRF_OPENDATA=1`. The open-data variant is a superset: same
    WRF/WPS plus the ECMWF ungrib patches (`rd_grib2.F` +
    `Vtable.ECMWF_GRIB2_opendata`) needed to decode the ECMWF open-data GRIB2.
- **runtime stage** — installs only the Intel oneAPI **runtime redistributables**
  (`intel-oneapi-runtime-*`, no compilers) and copies the compiled executables,
  runtime data and shared libraries from the builder. `openssh-client` is
  included for Intel MPI's multi-node SSH bootstrap, and `libeccodes-tools`
  (ecCodes `grib_set`/`grib_get`) for the open-data `download_bc.sh`, which
  repacks CCSDS GRIB2 to `grid_simple` for ungrib.

All three run-script sets are bundled so one image can drive any of them (see
[Run-script variants](#run-script-variants)):
`run_scripts`, `run_scripts_large`, `run_scripts_opendata`.

Fixed install prefix `/opt/arw` (not `$HOME`) so the image works under any
Apptainer user. Large static data (GEOG, boundary conditions, run output) is
**bind-mounted at run time**, not baked into the image.

## Prerequisites

- Docker (or a compatible daemon) **and** Apptainer on the build host.
- Network access during the build (Intel APT repo + WRF/WPS/library sources).
- Apptainer on every node where the container will run.

Install the toolchain on Ubuntu 24.04 or Rocky/RHEL 9 with the helper scripts:

```bash
./docker/install_docker.sh       # Docker Engine (build host)
./docker/install_apptainer.sh    # Apptainer (build host + run nodes)
```

The helper and launcher scripts must be executable. If you get
`permission denied` (e.g. running `./docker/run_apptainer.sh`), add the exec bit
once after cloning:

```bash
chmod +x docker/*.sh
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

To build the **ECMWF open-data** WPS variant (patched ungrib, see
[Run-script variants](#run-script-variants)):

```bash
WRF_OPENDATA=1 ./docker/build_sif.sh
```

To build only the Docker image (no SIF):

```bash
docker build -f docker/Dockerfile -t clam-wrf:latest .                       # plain
docker build -f docker/Dockerfile --build-arg WRF_OPENDATA=1 -t clam-wrf:latest .   # open data
```

## Run-script variants

All three run-script sets are baked into the image under `/opt/arw`. Pick one at
run time with `RUN_VARIANT` (see [section 3](#3-runtime-test)):

| `RUN_VARIANT` | Bundled dir | Initial/boundary conditions | Image build |
|---------------|-------------|-----------------------------|-------------|
| `default` *(default)* | `run_scripts` | plain sample dataset | plain or open-data |
| `large` | `run_scripts_large` | larger domain, same sample dataset | plain or open-data |
| `opendata` | `run_scripts_opendata` | ECMWF open data (IFS 0.25° GRIB2) | **`WRF_OPENDATA=1`** |

The `opendata` variant requires an image built with `WRF_OPENDATA=1` (patched
ungrib) and **network access at run time**: its `main_wrf.sh` downloads the
boundary conditions for the requested cycle and repacks them with ecCodes
`grib_set` (bundled in the image).

## 2. Prepare the host data directory

The container filesystem is read-only; all writable state lives on a
bind-mounted host directory (`DATA_DIR`), exposed as `/data`:

```text
$DATA_DIR/GEOG   # WPS_GEOG static data (from build_scripts/04_download_wps_geog.sh)
$DATA_DIR/BC     # boundary-condition GRIB files (from run_scripts/download_bc.sh)
$DATA_DIR/RUNS   # run directories / model output (writable, empty)
```

Stage it on the host with the repository scripts, pointing `ARW_ROOT` at
`DATA_DIR` (the download scripts only touch the `GEOG` and `BC` subdirs):

```bash
export DATA_DIR=/data/clam        # host path, adjust as needed

# GEOG (large, mandatory high-res) -> $DATA_DIR/GEOG/WPS_GEOG
ARW_ROOT="$DATA_DIR" ./build_scripts/04_download_wps_geog.sh

# BC (EUROPE sample) -> $DATA_DIR/BC/ECMWF_*.grb
ARW_ROOT="$DATA_DIR" ./run_scripts/download_bc.sh

# RUNS: empty and writable; main_wrf.sh creates the <cycle> subdir itself
mkdir -p "$DATA_DIR/RUNS"
```

Resulting layout:

```text
$DATA_DIR/
├── GEOG/
│   └── WPS_GEOG/                 # extracted mandatory high-res fields
├── BC/
│   └── ECMWF_20180601_00*.grb    # must match RUN_DATE/CYC in main_wrf.sh
└── RUNS/                         # empty; run dir created at run time
```

Notes:
- **Match the date.** `main_wrf.sh` links boundary conditions as
  `ECMWF_${RUN_DATE}${CYC}*.grb` (defaults `20180601`, `00Z`, EUROPE). If you
  change `RUN_DATE`/`CYC`, download BC for that date or the link finds nothing.
- **Open-data variant (`RUN_VARIANT=opendata`).** Do **not** pre-stage `BC/`:
  its `main_wrf.sh` downloads the ECMWF open-data GRIB2 for the requested cycle
  into `$DATA_DIR/BC` at run time (needs network + ecCodes, both in the image).
  Only `GEOG/` and an empty writable `RUNS/` are required on the host.
- **Permissions.** Rootless Apptainer runs as your UID, so `$DATA_DIR` and its
  subdirectories must be writable by your user (they are if you created them).
- Inside the container these map to `$ARW_ROOT/{GEOG,BC,RUNS}` with
  `ARW_ROOT=/opt/arw` (via the bind mount / symlinks).

## 3. Runtime test

The launcher `docker/run_apptainer.sh` reads three environment variables, all
with sensible defaults, so you can place the image and data wherever you like:

| Variable | Meaning | Default |
|----------|---------|---------|
| `IMG` | Path to the image to run — a **SIF file** or a **sandbox directory** | `clam-wrf.sif` |
| `DATA_DIR` | Host dir holding `GEOG/ BC/ RUNS/`, bound to `/data` | `$PWD/data` |
| `RUN_VARIANT` | Bundled run-script set: `default` \| `large` \| `opendata` | `default` |
| `RUN_SCRIPTS` | Optional host run-scripts dir to override the selected variant | *(use bundled)* |

```bash
# Example: SIF and data on another disk
IMG=/mnt/data1/clam-wrf.sif DATA_DIR=/mnt/data1/clam ./docker/run_apptainer.sh
```

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

The image bundles the `run_scripts` and symlinks `$ARW_ROOT/{GEOG,BC,RUNS}` to
the `/data` bind mount, so a **single bind of `DATA_DIR`** is all that is needed.
Run the full pipeline (WPS → real → wrf) with no arguments:

```bash
# Full pipeline via the bundled main_wrf.sh
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh

# Larger domain (same sample dataset)
RUN_VARIANT=large DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh

# ECMWF open data (needs an image built with WRF_OPENDATA=1 and network access).
# main_wrf.sh downloads + repacks the boundary conditions itself.
RUN_VARIANT=opendata DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh

# Interactive shell inside the container
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh bash

# Or drive individual steps from a prepared run directory:
DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh bash -c '
  cd /opt/arw/RUNS/<cycle>
  ungrib.exe && geogrid.exe && metgrid.exe
  mpirun -np 4  real.exe
  mpirun -np 16 wrf.exe
'
```

To tweak `RUN_DATE`/`CYC`/IPs without rebuilding, point `RUN_SCRIPTS` at a host
copy to override the selected variant:

```bash
RUN_SCRIPTS=$PWD/run_scripts DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh
RUN_VARIANT=opendata RUN_SCRIPTS=$PWD/run_scripts_opendata DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh
```

Success is `wrfout_d01_*` files in the run directory and `SUCCESS COMPLETE WRF`
in `rsl.out.0000`.

> `run_apptainer.sh` sources `$ARW_ROOT/arw_intel_env.sh` and adds the binary
> dirs to `PATH` automatically. `main_wrf.sh` creates and fills the `<cycle>`
> run directory itself — do not run `wrf.exe` in an empty folder.

### 3c. Running from a sandbox (when the SIF won't FUSE-mount)

On hosts where rootless Apptainer cannot mount the SIF (broken
`fuse-overlayfs`/squashfuse — see Troubleshooting), build a plain-directory
sandbox and point `IMG` at it; everything else is identical:

```bash
apptainer build --sandbox clam-sbx clam-wrf.sif      # or: SANDBOX=1 ./docker/build_sif.sh
IMG=clam-sbx DATA_DIR=$DATA_DIR ./docker/run_apptainer.sh
```

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

- **`stat /usr/bin/ls: no such file or directory` + warnings that
  `passwd`/`group`/`/tmp` "don't exist in container"** — the SIF's root
  filesystem is empty: the `docker-daemon://` conversion (common under rootless
  Apptainer) failed to extract the base layers. Rebuild via a saved archive
  (`build_sif.sh` already does this):
  ```bash
  docker save clam-wrf:latest -o clam-wrf.tar
  apptainer build clam-wrf.sif docker-archive://clam-wrf.tar
  ```
  Verify the Docker image itself is intact first:
  `docker run --rm clam-wrf:latest /usr/bin/ls /opt/arw`.
- **`"ls": executable file not found in $PATH`** — `$PATH` is empty in the
  container (host env passed through by Apptainer/MPI). The image sets an
  explicit `PATH`; otherwise run with `--cleanenv` or `--env PATH=...`.
- **`mpirun: command not found`** — the launcher lives in `intel-oneapi-mpi`
  (the runtime-only `intel-oneapi-runtime-mpi` ships MPI libraries but no
  `mpirun`/Hydra). The runtime stage installs `intel-oneapi-mpi`; make sure the
  environment is sourced (`source /opt/arw/arw_intel_env.sh`), which the run
  scripts and `run_apptainer.sh` do automatically.
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
