# Ansible playbook for CLAM WRF/WPS (build or deploy)

This directory is a single Ansible playbook with **two modes**, selected by
the boolean `clam_use_container` in
[`group_vars/all.yml`](group_vars/all.yml) (default `true`):

| `clam_use_container` | What runs | Roles |
|----------------------|-----------|-------|
| `true` (default)     | **Deploy** the prebuilt Apptainer image + run scripts to one or more run nodes. Does *not* compile anything. | `apptainer`, `intel_mpi`, `sif_deploy`, `run_scripts_deploy` |
| `false`              | **Build** WRF/WPS from source — the Ansible version of [`build_scripts/`](../build_scripts/). | `system_packages`, `intel_oneapi`, `arw_libs`, `wrf_wps`, `wps_geog`, `eccodes` |

The two sets of roles and variables are disjoint; the selector simply gates
which set runs. Pick the mode on the command line (`-e clam_use_container=…`)
or per host in the inventory.

## Requirements

On the control node (where you run Ansible):

```bash
sudo apt install -y ansible          # or: pipx install ansible-core
```

Only `ansible-core` is needed — the playbook uses `ansible.builtin` modules
only, so no Galaxy collections are required.

Each target host is Ubuntu 24.04 with SSH access as a normal user with
passwordless `sudo`. The target can be the control node itself (see
`localhost` in the inventory example).

```bash
cd ansible
cp inventory/hosts.ini.example inventory/hosts.ini
$EDITOR inventory/hosts.ini
```

---

## Container deploy mode (`clam_use_container=true`, default)

Deploys the **prebuilt** Apptainer image and the run scripts. The heavy build
happens once when you build the SIF with
[`../container/build_sif.sh`](../container/build_sif.sh); this playbook then
installs Apptainer and copies the SIF + launcher scripts to each run node.

| Role                 | Purpose |
|----------------------|---------|
| `apptainer`          | Installs Apptainer (mirrors [`../container/install_apptainer.sh`](../container/install_apptainer.sh)); ensures rootless user namespaces. |
| `intel_mpi`          | Installs the host **Intel MPI** launcher (`mpirun`/Hydra). **Only runs when `clam_install_oneapi=true`** — needed for multi-node runs. |
| `sif_deploy`         | Provides `clam-wrf.sif` on each target: **copies** a prebuilt file, or **builds** it from a container registry reference (`clam_sif_registry`). |
| `run_scripts_deploy` | Copies the launcher scripts and the `run_scripts*` variants, creates the `GEOG/ BC/ RUNS/` data skeleton, and (optionally) downloads the high-res WPS static data into `GEOG/WPS_GEOG`. |

You need the prebuilt image on the control node first:

```bash
./container/build_sif.sh             # from the repo root; produces clam-wrf.sif
```

```bash
# Install Apptainer + deploy the SIF and run scripts to all hosts:
ansible-playbook site.yml

# Multi-node hosts: also install the host Intel MPI launcher (same release as
# the image) so run_multinode.sh can drive mpirun across nodes:
ansible-playbook site.yml -e clam_install_oneapi=true

# Point at a SIF that is not at the repo root, and use the data volume:
ansible-playbook site.yml \
  -e clam_sif_src=/mnt/data1/clam-wrf.sif \
  -e clam_deploy_dir=/opt/clam \
  -e clam_data_dir=/data/clam

# Build the SIF ON THE TARGET from a container registry instead of copying it:
ansible-playbook site.yml -e clam_sif_registry=docker://ghcr.io/org/clam-wrf:latest
```

Tags: `--tags apptainer` (Apptainer only), `--tags oneapi` (host Intel MPI
only), `--tags deploy` (copy SIF + scripts only), `--tags geog` /
`--skip-tags geog` (the WPS static-data download).

**Single node vs. multi node.** Single-node runs need **only Apptainer** —
everything the model links against is baked into the SIF; leave
`clam_install_oneapi=false` (default). Multi-node runs use
[`run_multinode.sh`](../container/run_multinode.sh), which launches `mpirun`
**on the host**, so multi-node hosts also need the host Intel MPI launcher of
the **same release as the image** (`clam_install_oneapi=true`; pin with
`intel_mpi_version`, default `2026.0`).

### Providing the SIF: copy vs. registry build

`sif_deploy` has two mutually exclusive modes: **copy (default)** when
`clam_sif_registry` is empty (a prebuilt SIF at `clam_sif_src` is copied to
each target), or **build from a registry** when `clam_sif_registry` is set
(`apptainer build` runs on each target; `clam_sif_src` is ignored). For a
private registry set `clam_registry_username` and pass the password
non-interactively via `-e clam_registry_password=…` or an encrypted
`-e @vault.yml` (the build task runs with `no_log`).

### Container-mode variables

Most are in [`group_vars/all.yml`](group_vars/all.yml); the `clam_geog_*`
variables are [`run_scripts_deploy`](roles/run_scripts_deploy/defaults/main.yml)
role defaults.

| Variable            | Meaning                                                      | Default |
|---------------------|--------------------------------------------------------------|---------|
| `clam_sif_src`      | SIF path on the **control node** (copy mode)                 | `../clam-wrf.sif` |
| `clam_sif_dest`     | SIF path on the **target**                                   | `{{ clam_deploy_dir }}/clam-wrf.sif` |
| `clam_sif_registry` | Build the SIF on the target from this registry ref; empty = copy | `""` |
| `clam_sif_force_build` | Rebuild from the registry even if the SIF already exists   | `false` |
| `clam_registry_username` / `clam_registry_password` | Credentials for a **private** registry (registry build only) | `""` |
| `clam_deploy_dir`   | Where launcher scripts + run_scripts land on the target      | `~/clam-ewc` |
| `clam_data_dir`     | Host dir bound into the container at `/data` (`GEOG/BC/RUNS`) | `~/clam-data` |
| `clam_download_geog` | Download the mandatory high-res WPS static data during deploy (idempotent) | `true` |
| `clam_run_variants` | Which run-script variants to deploy                          | `default`, `large`, `opendata` |
| `apptainer_version` | Empty = Ubuntu `apptainer/ppa`; set e.g. `1.3.6` for the GitHub `.deb` | `""` |
| `clam_install_oneapi` | Install the host Intel MPI launcher (`intel_mpi` role). **Set `true` for multi-node hosts.** | `false` |
| `intel_mpi_version` | Intel MPI release pinned on the host to match the image      | `2026.0` |

After deployment, stage boundary-condition data under `clam_data_dir` and
launch from the deploy dir; see [`../container/README.md`](../container/README.md)
for the full run reference.

---

## Source build mode (`clam_use_container=false`)

Installs exactly the same software stack as [`build_scripts/`](../build_scripts/)
— Ubuntu build packages, Intel oneAPI, the third-party libraries, WRF, WPS, the
WPS static geographical data and, optionally, ecCodes. The shell scripts remain
the reference implementation; use this mode to build several VMs from one place
and re-run steps idempotently.

The full stack with the high-resolution static data needs roughly 60 GB under
`arw_root`. The build takes several hours, most of it in the WRF compile — run
it under `tmux`, `screen` or `nohup`.

```bash
# The whole build, sample initial and boundary conditions:
ansible-playbook site.yml -e clam_use_container=false

# On EWC, with the stack on the data volume:
ansible-playbook site.yml -e clam_use_container=false -e arw_root=/data/ARW

# ECMWF open data GRIB2 variant, which also installs ecCodes:
ansible-playbook site.yml -e clam_use_container=false -e arw_root=/data/ARW -e wps_ecmwf_opendata=true
```

### What maps to what

| Role              | Shell script                                        |
|-------------------|-----------------------------------------------------|
| `system_packages` | `00_install_system_packages.sh`                     |
| `intel_oneapi`    | `01_install_intel_oneapi.sh`                        |
| `arw_libs`        | `02_install_arw_third_party_libs.sh`                |
| `wrf_wps`         | `03_install_wrf_wps.sh`                             |
| `wrf_wps` with `wps_ecmwf_opendata=true` | `03_install_wrf_wps_openData.sh` |
| `wps_geog`        | `04_download_wps_geog.sh`                           |
| `eccodes`         | `05_install_eccodes.sh` (optional)                  |

Each role carries tags, so a single step can be run on its own (all combined
with `-e clam_use_container=false`):

```bash
ansible-playbook site.yml -e clam_use_container=false --tags packages
ansible-playbook site.yml -e clam_use_container=false --tags oneapi
ansible-playbook site.yml -e clam_use_container=false --tags libs
ansible-playbook site.yml -e clam_use_container=false --tags wrf          # WRF only
ansible-playbook site.yml -e clam_use_container=false --tags wps          # WPS only
ansible-playbook site.yml -e clam_use_container=false --tags wrf_wps      # both
ansible-playbook site.yml -e clam_use_container=false --tags geog
ansible-playbook site.yml -e clam_use_container=false --tags eccodes -e install_eccodes=true
```

`arw_libs` writes the same `${ARW_ROOT}/arw_intel_env.sh` the shell scripts
write, from
[`roles/arw_libs/templates/arw_intel_env.sh.j2`](roles/arw_libs/templates/arw_intel_env.sh.j2);
the `run_scripts/` keep working against it.

Because ansible provisions from the control node (the repo is not checked out
on the target), the `wrf_wps` role also **copies the run-script variants to
`$ARW_ROOT`** — `arw_run_variants` (default `run_scripts`, `run_scripts_large`,
`run_scripts_opendata`) — so a source-built VM can drive a run in place, e.g.
`cd $ARW_ROOT/run_scripts && ARW_ROOT=$ARW_ROOT ./main_wrf.sh`. The shell
workflow instead runs them from the repo clone.

### Source-mode variables

The main ones, from [`group_vars/all.yml`](group_vars/all.yml):

| Variable              | Default              | Meaning                                    |
|-----------------------|----------------------|--------------------------------------------|
| `arw_root`            | `$HOME/ARW`          | installation root, as `ARW_ROOT`           |
| `arw_build_jobs`      | `4`                  | `make -j` for the third-party libraries     |
| `wps_ecmwf_opendata`  | `false`              | patch `ungrib` for ECMWF open data GRIB2    |
| `install_eccodes`     | `wps_ecmwf_opendata` | install ecCodes as well                     |
| `wrf_force_rebuild`   | `false`              | clean and rebuild WRF even if built         |
| `wps_force_rebuild`   | `false`              | clean and rebuild WPS even if built         |
| `arw_run_variants`    | all three            | run-script variants copied to `$ARW_ROOT`   |

Versions, download mirrors and the ecCodes options live in each role's
`defaults/main.yml`. The Intel oneAPI offline installer (~20 GB) can be
provided instead of downloaded via `-e oneapi_installer=…` (on the target) or
`-e oneapi_installer_src=…` (copied from the control node).

### How it differs from the shell scripts

* **Re-running is cheap.** WRF/WPS skip the configure/compile steps if
  `wrf.exe`/`ungrib.exe` already exist; use `-e wrf_force_rebuild=true` /
  `-e wps_force_rebuild=true` for the scripts' always-rebuild behaviour.
  Switching `wps_ecmwf_opendata` on later forces the WPS rebuild by itself.
* **Privileges are per task.** The play runs as the ordinary build user; only
  tasks that need it escalate. Do not run with `--become` for the whole play.
* **The long steps run with `async`**, so a brief network problem does not kill
  a two-hour build; the full logs are in
  `${ARW_ROOT}/WRF/compile_wrf_461_safe.log` and
  `${ARW_ROOT}/WPS/compile_wps_460.log`.
* **ecCodes tests** are reported but never fatal (`Test suite:` in the summary).

A download mirror that is down prints a red `fatal: ... ignoring` line and the
build carries on with the next mirror, as `download_with_fallbacks` in script 02
does. It is only a real failure if the task *Fail when no mirror provided …*
follows it.

---

## Checking the playbook

```bash
ansible-playbook -i inventory/hosts.ini site.yml --syntax-check
ansible-playbook -i inventory/hosts.ini site.yml --list-tasks                        # container (default)
ansible-playbook -i inventory/hosts.ini site.yml -e clam_use_container=false --list-tasks  # source build
ansible-lint                     # if installed
```

Ansible's default output is terse for long compiles. The nicer YAML output
needs one collection, which is otherwise not required:

```bash
ansible-galaxy collection install community.general
ANSIBLE_STDOUT_CALLBACK=community.general.yaml ansible-playbook site.yml
```

`--check` (dry run) is *not* useful for the source build: the later steps
inspect files that earlier steps create, so a check run reports failures on a
machine that has not been built yet.
