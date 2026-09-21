# Develop CUDA code on an NVIDIA GPU

The shipped `cuda-development` skill lets Claude, Codex and Pi build and run
CUDA code on the host's NVIDIA GPUs. The host supplies the driver. An
optional installer adds the CUDA toolkit to the container.

## Start the container with a GPU

Start the project container with GPU access, from the host:

```bash
claude-sandbox --recreate --gpu
```

The host needs a working NVIDIA driver and the NVIDIA Container Toolkit. See
[GPUs and other devices](use-the-container-image.md#gpus-and-other-devices)
for Podman CDI setup. Run `nvidia-smi` in `claude-sandbox shell` to check the
container.

## Install the toolkit

Open `claude-sandbox shell` from your project on the host, or use a
devcontainer terminal. Review and run this script there as root,
**outside the agent sandbox**:

```bash
bash /usr/libexec/claude-sandbox/skills/cuda-development/scripts/install-cuda-toolkit.sh
```

The script works on Ubuntu and Debian containers, on x86_64 and arm64
servers. It does these things:

1. It adds NVIDIA's apt repository for the container's release.
2. It pins every NVIDIA driver package out of apt, so that nothing replaces
   the driver files the host mounts in.
3. It picks the newest toolkit that the host driver supports.
4. It installs `nvcc`, the CUDA runtime, the math libraries and the
   command-line debug and profiling tools, about 5 GiB in total.
5. It links the tools into `/usr/local/bin` and runs a GPU smoke test.

Add a version such as `12.8` to install that release instead. Add
`--minimal` for `nvcc` and the runtime only, or `--full` for the whole
toolkit with the Nsight GUIs. Rerun the script after container recreation.
No agent restart is needed for the installed tools.

Do not install Ubuntu's `nvidia-cuda-toolkit` package. The package depends
on a driver library that clashes with the host's driver, and the failed
install leaves apt broken. The installer's pin refuses it.

## Ask the agent

Ask the agent to run the skill's smoke test, then give it the real task:

> Check that CUDA works in the sandbox, then build the project's GPU tests
> and run them.

The smoke test lists the GPUs and adds two vectors on the first one.

PyTorch and similar frameworks ship their own CUDA runtime in their wheels.
They need the driver but not this toolkit, unless the project compiles its
own CUDA extensions.

Device access widens the sandbox's trust boundary. Read the warning in
[GPUs and other devices](use-the-container-image.md#gpus-and-other-devices)
before you enable it.
