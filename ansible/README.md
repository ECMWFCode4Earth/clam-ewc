# Ansible playbook for the CLAM WRF/WPS build

This directory is an Ansible version of the scripts in
[`build_scripts/`](../build_scripts/). It installs exactly the same
software stack — Ubuntu build packages, Intel oneAPI, the third-party
libraries, WRF, WPS, the WPS static geographical data and, optionally,
ecCodes — on one or more Ubuntu 24.04 machines.

The shell scripts remain the reference implementation. Use the playbook
when you want to build several VMs from one place, re-run a step without
worrying about what was already done, or keep the build settings in one
file instead of in environment variables.

## Requirements

On the machine you run Ansible *from* (the control node):

```bash
sudo apt install -y ansible          # or: pipx install ansible-core
```

Only `ansible-core` is needed — the playbook uses `ansible.builtin`
modules only, so no Galaxy collections have to be installed.

On the machine being built (the target):

* Ubuntu 24.04
* SSH access as a normal user with passwordless `sudo`
* enough disk space under `arw_root` (the full stack with the high
  resolution static data needs roughly 60 GB)

The target can be the control node itself; see `localhost` in the
inventory example.

## Quick start

```bash
cd ansible
cp inventory/hosts.ini.example inventory/hosts.ini
$EDITOR inventory/hosts.ini

# The whole build, sample initial and boundary conditions:
ansible-playbook site.yml

# On EWC, with the stack on the data volume:
ansible-playbook site.yml -e arw_root=/data/ARW

# ECMWF open data GRIB2 variant, which also installs ecCodes:
ansible-playbook site.yml -e arw_root=/data/ARW -e wps_ecmwf_opendata=true
```

The full build takes several hours, most of it in the WRF compile. Run
it under `tmux`, `screen` or `nohup` so that a dropped connection from
your workstation does not interrupt it.

## What maps to what

| Role              | Shell script                                        |
|-------------------|-----------------------------------------------------|
| `system_packages` | `00_install_system_packages.sh`                     |
| `intel_oneapi`    | `01_install_intel_oneapi.sh`                        |
| `arw_libs`        | `02_install_arw_third_party_libs.sh`                |
| `wrf_wps`         | `03_install_wrf_wps.sh`                             |
| `wrf_wps` with `wps_ecmwf_opendata=true` | `03_install_wrf_wps_openData.sh` |
| `wps_geog`        | `04_download_wps_geog.sh`                           |
| `eccodes`         | `05_install_eccodes.sh` (optional)                  |

Each role carries tags, so a single step can be run on its own:

```bash
ansible-playbook site.yml --tags packages
ansible-playbook site.yml --tags oneapi
ansible-playbook site.yml --tags libs
ansible-playbook site.yml --tags wrf,wps
ansible-playbook site.yml --tags geog
ansible-playbook site.yml --tags eccodes -e install_eccodes=true
```

The build decisions that the shell scripts arrived at are kept as they
are: WRF is built `dmpar` with `mpiifx`/`mpiicx`, with `-ip` removed from
the compiler flags and with `-j 1`; WPS is built serial and linked
against JasPer 1.900.1 for `ungrib.exe`; HDF5 is built parallel with
Fortran support. The WRF and WPS `configure` menus are parsed rather
than answered with a hard-coded number, as in the scripts, so a WRF or
WPS version bump does not silently select the wrong compiler.

`arw_libs` writes the same `${ARW_ROOT}/arw_intel_env.sh` that the shell
scripts write, from
[`roles/arw_libs/templates/arw_intel_env.sh.j2`](roles/arw_libs/templates/arw_intel_env.sh.j2).
The `run_scripts/` are unchanged and keep working against it.

## Variables

The main ones, from [`group_vars/all.yml`](group_vars/all.yml):

| Variable              | Default              | Meaning                                    |
|-----------------------|----------------------|--------------------------------------------|
| `arw_root`            | `$HOME/ARW`          | installation root, as `ARW_ROOT`           |
| `arw_build_jobs`      | `4`                  | `make -j` for the third-party libraries     |
| `wps_ecmwf_opendata`  | `false`              | patch `ungrib` for ECMWF open data GRIB2    |
| `install_eccodes`     | `wps_ecmwf_opendata` | install ecCodes as well                     |
| `wrf_force_rebuild`   | `false`              | clean and rebuild WRF even if built         |
| `wps_force_rebuild`   | `false`              | clean and rebuild WPS even if built         |

Versions, download mirrors and the ecCodes options live in each role's
`defaults/main.yml`. Anything can be overridden per host in the
inventory or on the command line with `-e`:

```bash
ansible-playbook site.yml -e wrf_version=v4.8.0 -e wps_version=v4.7.0
ansible-playbook site.yml --tags eccodes -e install_eccodes=true -e eccodes_version=2.48.0
```

### Air-gapped or slow links

The Intel oneAPI offline installer (around 20 GB) can be provided
instead of downloaded:

```bash
# already on the target host
ansible-playbook site.yml -e oneapi_installer=/data/intel-oneapi-toolkit-2026.0.0.198_offline.sh

# on the control node, copied to the target first
ansible-playbook site.yml -e oneapi_installer_src=~/Downloads/intel-oneapi-toolkit-2026.0.0.198_offline.sh
```

## How it differs from the shell scripts

* **Re-running is cheap.** The libraries keep the "is it already
  installed?" checks of the scripts. WRF and WPS go further: if
  `wrf.exe`/`ungrib.exe` already exist, the configure and compile steps
  are skipped instead of always running `./clean -a` and rebuilding. Use
  `-e wrf_force_rebuild=true` or `-e wps_force_rebuild=true` for the
  scripts' always-rebuild behaviour. Switching `wps_ecmwf_opendata` on
  later forces the WPS rebuild by itself, because `rd_grib2.F` changes.
* **Privileges are per task.** The play runs as the ordinary build user,
  and only the tasks that need it escalate (`apt`, the oneAPI system
  install, `make install` into `/usr/local`, `ldconfig`). Everything
  under `arw_root` therefore belongs to the build user, as with the
  scripts. Do not run the playbook with `--become` for the whole play.
* **The long steps run with `async`.** The compiles and the oneAPI
  installer are started detached and polled, so a brief network problem
  between the control node and the VM does not kill a two-hour build.
  Their output appears when the task finishes; the full WRF and WPS
  compile logs are in `${ARW_ROOT}/WRF/compile_wrf_461_safe.log` and
  `${ARW_ROOT}/WPS/compile_wps_460.log` as before.
* **`ulimit -s unlimited`** in `arw_intel_env.sh` is allowed to fail
  rather than aborting the build, for the tasks that source the file
  under `set -e`.
* **ecCodes tests** are reported but never fatal, as in the script. Look
  for `Test suite:` in the final summary.

## Checking the playbook

```bash
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --list-tasks
ansible-lint                     # if installed
```

`--check` (dry run) is *not* useful for this playbook: the later steps
inspect files that earlier steps create, so a check run reports failures
on a machine that has not been built yet.
