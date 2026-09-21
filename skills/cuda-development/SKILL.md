---
name: cuda-development
description: Set up and check NVIDIA CUDA development inside claude-sandbox — nvcc, the CUDA runtime and math libraries, and a GPU smoke test. Use when a task needs nvcc or CUDA headers, when nvidia-smi works but CUDA programs fail, or before anyone proposes installing a GPU driver or Ubuntu's nvidia-cuda-toolkit in the container.
---

# CUDA development

The host supplies the NVIDIA driver. The container runtime mounts its
libraries and `nvidia-smi` into the container when the user starts it with
`claude-sandbox --gpu`. The toolkit (`nvcc`, headers, cuBLAS and the other
libraries) is not in the image and needs an install in the outer container.

## Check first

Run `nvidia-smi` in the sandbox. If it is missing or fails, the container has
no GPU. Ask the user to recreate it with GPU access, from the host:

```sh
claude-sandbox --recreate --gpu
```

A Podman host that reports `unresolvable CDI devices` needs the CDI setup in
the container-image guide first. Recreation loses packages installed in the
outer container, so recreate before the toolkit install, not after.

If `nvcc` is missing, go to Setup.

## Setup

Ask the user to run the installer as root in the outer container
(`claude-sandbox shell` or a devcontainer terminal):

```sh
bash /usr/libexec/claude-sandbox/skills/cuda-development/scripts/install-cuda-toolkit.sh
```

Explain these changes before you ask. The installer:

- adds NVIDIA's apt repository for the container's Ubuntu or Debian release;
- pins every NVIDIA driver package out of apt, because a driver in the
  container clashes with the one the host mounts in;
- picks the newest toolkit that the host driver supports, as `nvidia-smi`
  reports it;
- installs about 5 GiB under `/usr/local/cuda-<version>` and links the tools
  into `/usr/local/bin`;
- compiles and runs the smoke test in the outer container.

Options, which the user can combine:

- a version such as `12.8` installs that release instead, to match a project;
- `--minimal` installs `nvcc` and the runtime only (about 0.5 GiB);
- `--full` installs the whole `cuda-toolkit`, with the Nsight GUIs (about 7 GiB);
- `--no-smoke` skips the smoke test.

The install lasts until the container is recreated. The script can be run
again after that. No agent restart is needed to see the new files.

Never install a driver package (`nvidia-driver-*`, `libnvidia-compute-*`,
`cuda-drivers`) or Ubuntu's `nvidia-cuda-toolkit`, which depends on one. The
install fails in `dpkg` and leaves apt broken. The installer's pin refuses
them. Do not run the installer in the jail or copy it to a writable location.
For development before the skill is installed, give its absolute path in the
shared checkout instead.

## Verify

Inside the sandbox, run the bundled smoke script:

```sh
bash /usr/libexec/claude-sandbox/skills/cuda-development/scripts/cuda-smoke.sh
```

It lists the GPUs, adds two vectors on device 0 and ends with `PASS`. Give an
output directory as the sole argument to keep the binary. A passing smoke
test proves the toolkit and GPU access, not the project's own code.

## Use

Build with the project's normal commands. `nvcc` is on `PATH`, and
`/usr/local/cuda` points at the installed toolkit. Set `CUDA_HOME` in the
agent shell if a build system asks for it:

```sh
export CUDA_HOME=/usr/local/cuda
```

Python frameworks such as PyTorch bring their own CUDA runtime in their
wheels. They need only the driver, so install them in the project venv with
`uv` as usual. Their CUDA build must not be newer than the version
`nvidia-smi` reports.

A CUDA error such as `cudaErrorOperatingSystem` or `CUDA_ERROR_NO_DEVICE`
while `nvidia-smi` works points at device access, not at the toolkit. Report
the exact error and the smoke-test output to the user.
