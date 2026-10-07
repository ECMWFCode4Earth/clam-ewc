# Ansible playbook for deploying the CLAM WRF/WPS container

This directory deploys the **prebuilt** Apptainer image and the run scripts to
one or more Ubuntu 24.04 hosts. It is the deployment counterpart to the
[`../ansible`](../ansible/) playbook (which *builds* WRF/WPS from source) and to
the [`../container`](../container/) image build.

It does **not** compile anything: the heavy build happens once when you build the
SIF with [`../container/build_sif.sh`](../container/build_sif.sh). This playbook
then installs Apptainer and copies the SIF + launcher scripts to each run node.

## What it does

| Role                 | Purpose                                                            |
|----------------------|-------------------------------------------------------------------|
| `apptainer`          | Installs Apptainer (mirrors [`../container/install_apptainer.sh`](../container/install_apptainer.sh)); ensures rootless user namespaces. |
| `intel_mpi`          | Installs the host **Intel MPI** launcher (`mpirun`/Hydra) from the Intel oneAPI APT repo. **Only runs when `clam_install_oneapi=true`** — needed for multi-node runs. |
| `sif_deploy`         | Provides `clam-wrf.sif` on each target: **copies** a prebuilt file from the control node, or **builds** it there from a container registry reference (`clam_sif_registry`). |
| `run_scripts_deploy` | Copies the launcher scripts (`run_apptainer.sh`, `run_multinode.sh`) and the `run_scripts*` variants, creates the `GEOG/ BC/ RUNS/` data skeleton, and (optionally) downloads the mandatory high-res WPS static data into `GEOG/WPS_GEOG`. |

### Single node vs. multi node

- **Single-node runs** need **only Apptainer** — everything the model links
  against is baked into the SIF. Leave `clam_install_oneapi=false` (the default).
- **Multi-node runs** use [`run_multinode.sh`](../container/run_multinode.sh),
  which launches `mpirun` **on the host**; `wrf.exe` inside the container uses the
  image's ABI-compatible Intel MPI. So multi-node hosts also need the host Intel
  MPI launcher, of the **same release as the image**. Enable it with
  `clam_install_oneapi=true`; the `intel_mpi` role installs it from the same
  Intel oneAPI APT repo the image is built from (see
  [`../container/Dockerfile`](../container/Dockerfile)).

  The host release is **pinned** via `intel_mpi_version` (default `2026.0`, the
  oneAPI release this repo tracks) so the host `mpirun` matches the container's
  Intel MPI ABI. Confirm the image's version and align the pin if you rebuilt
  with a different release:

  ```bash
  apptainer exec clam-wrf.sif bash -lc \
    'source /opt/intel/oneapi/setvars.sh >/dev/null; mpirun --version'
  # then, if needed:
  ansible-playbook site.yml -e clam_install_oneapi=true -e intel_mpi_version=<version>
  ```

## Requirements

On the machine you run Ansible *from* (the control node):

```bash
sudo apt install -y ansible          # or: pipx install ansible-core
```

Only `ansible-core` is needed — the playbook uses `ansible.builtin` modules only,
so no Galaxy collections are required.

You also need the prebuilt image on the control node:

```bash
# from the repository root (clam-ewc/)
./container/build_sif.sh             # produces clam-wrf.sif
```

On each target host:

* Ubuntu 24.04
* SSH access as a normal user with passwordless `sudo`
* enough disk space for the SIF and the model output under `clam_data_dir`

## Quick start

```bash
cd ansible_container
cp inventory/hosts.ini.example inventory/hosts.ini
$EDITOR inventory/hosts.ini

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
# Private registry: set the username and let the playbook PROMPT for the password
# (or pass it via Vault; see "Registry credentials"):
ansible-playbook site.yml \
  -e clam_sif_registry=docker://registry.example.com/clam-wrf:2026.0 \
  -e clam_registry_username=robot
```

Run only part of it with tags:

```bash
ansible-playbook site.yml --tags apptainer   # install Apptainer only
ansible-playbook site.yml --tags oneapi      # install host Intel MPI only
ansible-playbook site.yml --tags deploy      # copy SIF + scripts only
ansible-playbook site.yml --tags geog        # download WPS static data only
ansible-playbook site.yml --skip-tags geog   # everything except the GEOG download
```

## Variables

Most are defined in [`group_vars/all.yml`](group_vars/all.yml); the `clam_geog_*`
variables are [`run_scripts_deploy`](roles/run_scripts_deploy/defaults/main.yml)
role defaults. Override any of them with `-e` or in the inventory.

| Variable            | Meaning                                                      | Default |
|---------------------|--------------------------------------------------------------|---------|
| `clam_sif_src`      | SIF path on the **control node** (copy mode)                 | `../clam-wrf.sif` |
| `clam_sif_dest`     | SIF path on the **target**                                   | `{{ clam_deploy_dir }}/clam-wrf.sif` |
| `clam_sif_registry` | Build the SIF on the target from this registry ref (e.g. `docker://ghcr.io/org/clam-wrf:latest`); empty = copy from control node | `""` |
| `clam_sif_force_build` | Rebuild from the registry even if the SIF already exists   | `false` |
| `clam_registry_username` / `clam_registry_password` | Credentials for a **private** registry (registry build only). Password is prompted or passed via Vault/`-e` — see [Registry credentials](#registry-credentials) | `""` |
| `clam_deploy_dir`   | Where launcher scripts + run_scripts land on the target      | `~/clam-ewc` |
| `clam_data_dir`     | Host dir bound into the container at `/data` (`GEOG/BC/RUNS`) | `~/clam-data` |
| `clam_download_geog` | Download the mandatory high-res WPS static data into `{{ clam_data_dir }}/GEOG/WPS_GEOG` during deploy. Idempotent (skipped when `WPS_GEOG/` already exists). Set `false` to skip — see [Skipping the GEOG download](#skipping-the-geog-download). | `true` |
| `clam_geog_url`     | Source tarball for the static data (`geog_high_res_mandatory.tar.gz`) | UCAR WPS files URL |
| `clam_geog_remove_archive` | Delete the multi-GB tarball after unpacking                 | `true` |
| `clam_run_variants` | Which run-script variants to deploy                          | `default`, `large`, `opendata` |
| `apptainer_version` | Empty = Ubuntu `apptainer/ppa`; set e.g. `1.3.6` for the GitHub `.deb` | `""` |
| `clam_install_oneapi` | Install the host Intel MPI launcher (`intel_mpi` role). **Set `true` for multi-node hosts.** | `false` |
| `intel_mpi_version` | Intel MPI release pinned on the host to match the image (`intel-oneapi-mpi-<version>`); set `""` for the latest | `2026.0` |

## Providing the SIF: copy vs. build from a registry

`sif_deploy` supports two mutually exclusive modes:

- **Copy (default)** — `clam_sif_registry` empty. A prebuilt `clam-wrf.sif` on
  the control node (`clam_sif_src`) is copied to each target. Build it once with
  [`../container/build_sif.sh`](../container/build_sif.sh).
- **Build from a registry** — set `clam_sif_registry` to an OCI/ORAS reference
  and Ansible runs `apptainer build <dest> <ref>` **on each target**, pulling the
  image and assembling the SIF there (no large file copy over SSH). `clam_sif_src`
  is then ignored. Add `clam_sif_force_build=true` to rebuild over an existing
  SIF, and `clam_registry_username`/`clam_registry_password` for a private
  registry (the task sets `APPTAINER_DOCKER_*` and runs with `no_log`). The
  password is **not** stored in the repo: it is prompted at run time, or passed
  non-interactively (see [Registry credentials](#registry-credentials)).

```bash
# Public registry
ansible-playbook site.yml -e clam_sif_registry=docker://ghcr.io/org/clam-wrf:latest
# ORAS registry, forced rebuild
ansible-playbook site.yml \
  -e clam_sif_registry=oras://registry.example.com/clam-wrf:2026.0 \
  -e clam_sif_force_build=true
```

Building on the target needs Apptainer (installed by the `apptainer` role) and
network access to the registry from each node.

### Registry credentials

Public images need no credentials. For a **private** registry set
`clam_registry_username` (safe to keep in the inventory/group_vars) and provide
the password by one of:

- **Interactive prompt (default).** `site.yml` has a `vars_prompt` for
  `clam_registry_password`; just run the playbook and type it when asked (input
  is hidden). Press Enter to skip for public images. Non-interactive runs
  (no TTY, e.g. CI) use the empty default and do not hang.
- **Ansible Vault (non-interactive).** Keep the secret encrypted and pass it so
  it overrides the prompt:
  ```bash
  ansible-vault create secrets.yml      # add: clam_registry_password: "..."
  ansible-playbook site.yml --ask-vault-pass \
    -e @secrets.yml \
    -e clam_sif_registry=docker://registry.example.com/clam-wrf:2026.0 \
    -e clam_registry_username=robot
  ```
- **One-off `-e`.** `-e clam_registry_password=***` (visible in your shell
  history / process list — prefer the prompt or Vault).

The build task runs with `no_log`, so the password is never printed in task
output.

## Skipping the GEOG download

By default `run_scripts_deploy` downloads the mandatory high-res WPS static data
(several GB) into `{{ clam_data_dir }}/GEOG/WPS_GEOG` — the Ansible equivalent of
`ARW_ROOT=$DATA_DIR ./build_scripts/04_download_wps_geog.sh`. The step is
**idempotent**: it is skipped automatically when `GEOG/WPS_GEOG` already exists.

Skip it explicitly when the data is already staged or lives on a shared mount:

```bash
# One-off: skip the download for this run
ansible-playbook site.yml -e clam_download_geog=false

# Or by tag: run everything except the GEOG download
ansible-playbook site.yml --skip-tags geog

# Run only the GEOG download
ansible-playbook site.yml --tags geog
```

Set `clam_download_geog: false` in `group_vars/all.yml` to make the skip permanent.

## After deployment

Boundary-condition data still has to be staged under `clam_data_dir` (the GEOG
static data is downloaded by the playbook unless you skipped it). Then launch
from the deploy dir on a host. See [`../container/README.md`](../container/README.md)
for data staging and the full run reference.

```bash
# Single node
IMG=~/clam-ewc/clam-wrf.sif DATA_DIR=~/clam-data \
  ~/clam-ewc/container/run_apptainer.sh

# Multi node (SIF + DATA_DIR must be at the SAME path on every node,
# with passwordless SSH between them)
HOSTS=vm01,vm03 PPN=16 IMG=~/clam-ewc/clam-wrf.sif DATA_DIR=~/clam-data \
  ~/clam-ewc/container/run_multinode.sh
```

> **Multi-node note.** The deployed `run_multinode.sh` runs `mpirun` on the host
> and needs the host Intel oneAPI MPI (same release as the image). Install it by
> running the playbook with `-e clam_install_oneapi=true` on the run nodes (the
> `intel_mpi` role). Single-node runs need only Apptainer, so the default
> (`clam_install_oneapi=false`) leaves oneAPI off.
