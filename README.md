# UNC Charlotte ITSC 3146 virtual environment (WSL)

This repository is meant for Windows users. Mac or Linux users should use the [Lima version](https://github.com/jeffreyalanwang/ITSC_3146_Lima).

## Usage
### Install

1.  Install WSL:

    `wsl --install --no-distribution`

2.  [Download the latest image release](https://github.com/jeffreyalanwang/ITSC_3146_WSL/releases) and double-click on it.

**Full installation instructions & Getting Started:** [Google Doc](https://docs.google.com/document/d/1sqxhCL-XgVQ76An_PvmMUZ3INQ5uFnjl/edit?usp=sharing&ouid=103252777093034404109&rtpof=true&sd=true)

### Uninstall
`wsl --unregister ITSC-3146`

## Mechanics
Files in [/.github/](/.github/) configure the automated building and release of WSL images.

Files in [/cloud-init/](/cloud-init/) configure the initialization of our guest system.

Files in [/wsl/](/wsl/) are added to the image as configuration for WSL.

Files in [/X11/](/X11/) contain configuration for GUI applications such as xterm.

### Builds and releases
Locally build images using [/.github/workflows/build.sh](/.github/workflows/build.sh).

#### Build process
The build process downloads vanilla Ubuntu 24.04 WSL images. Its format is a renamed `.tar.gz` file.

We check the `copy_runtime_files` dictionary in [/build_config.json](/build_config.json), and copy files into the image accordingly. Keys represent repository paths, and values represent destination filesystem paths; both should begin with a slash `/`.

Build scripts are unit-tested:
* [/.github/workflows/test.sh](/.github/workflows/test.sh)
* [/.github/actions/add_archive_file/test.sh](/.github/actions/add_archive_file/test.sh)
* [/.github/actions/get_ubuntu_images/test.sh](/.github/actions/get_ubuntu_images/test.sh)

#### Release creation
Every commit to the `release` branch triggers a [GitHub Actions workflow](/.github/workflows/release.yml), which:
* Runs unit tests
* Builds images
* Creates a release, if tests pass

### Initialization
Our image build does not run the Linux system. Instead, we inject configuration for `cloud-init` to find and execute on first boot.

In `/etc/cloud/cloud.cfg.d/`, we override all other configuration and direct `cloud-init` to look in `/etc/CCI/cloud-init/` for our config. There, we are required to provide `meta-data` and `user-data` files (even if empty). We place our initialization commands in `vendor-data` to avoid surprise conflict with [WSL's mechanism](https://cloudinit.readthedocs.io/en/latest/reference/datasources/wsl.html) for users to inject their own `user-data` config.

### IMUNES installation
We currently install IMUNES from a mirror with a few bugfixes required for this course at:
https://github.com/jeffreyalanwang/imunes

### Networking
On first boot, [wsl-oobe-itsc.sh](/wsl/wsl-oobe-itsc.sh) configures WSL to use *mirrored networking* instead of the default NAT, for better host VPN support.

### Copy/paste
`xterm` is configured to copy and paste using the CLIPBOARD buffer instead of PRIMARY, and to use the keyboard shortcuts:
* Ctrl+Shift+C
* Ctrl+Shift+V
