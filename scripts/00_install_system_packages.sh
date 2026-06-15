#!/bin/bash
#=================================================================
# This script prepares a fresh Ubuntu 24.04 system for compiling 
# WRF, WPS and their required dependencies.
# The script installs the required Ubuntu packages, including:
#    • C, C++ and Fortran development tools
#    • GNU compilers and standard build utilities
#    • shell tools required by WRF/WPS
#    • archive and compression utilities
#    • system development headers
#    • wget, curl, git, rsync and other useful installation tools
#==================================================================
#!!!!!!  This script should be run first on a fresh VM. !!!!!!!!!
#==================================================================

sudo apt update

sudo apt install -y \
  build-essential \
  gcc \
  g++ \
  gfortran \
  make \
  m4 \
  perl \
  csh \
  tcsh \
  file \
  wget \
  curl \
  tar \
  gzip \
  bzip2 \
  xz-utils \
  patch \
  pkg-config \
  libc6-dev \
  linux-libc-dev

sudo apt install -y unzip
