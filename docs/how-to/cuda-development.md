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
[Podman setup](#podman-setup) below for CDI configuration. Run `nvidia-smi`
in `claude-sandbox shell` to check the container.

## Install the toolkit

Open `claude-sandbox shell` from your project on the host, or use a
devcontainer terminal. Review and run this script there as root,
**outside the agent sandbox**:

```bash
bash /usr/libexec/claude-sandbox/skills/cuda-development/scripts/install-cuda-toolkit.sh
```

On Ubuntu/Debian x86_64 and arm64 servers, the script adds NVIDIA's apt
repository, blocks driver packages, and installs the newest compatible
`nvcc` and runtime development files (about 0.5 GiB). It links tools into
`/usr/local/bin` and runs a GPU smoke test.

Add a version such as `12.8` to install that release instead. Add
`--dev` for math libraries and command-line debugging and profiling tools
(about 5 GiB total), or `--full` for the whole
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

## Podman setup

The host needs a working NVIDIA driver (`nvidia-smi`) and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
Podman uses the sandbox-specific CDI class `nvidia.com/sandbox-gpu=all`.
If it reports that this device is unresolvable, configure CDI on the **host**:

```bash
curl -fL -o setup-nvidia-cdi.sh \
  https://raw.githubusercontent.com/DiamondLightSource/claude-sandbox/main/container/setup-nvidia-cdi.sh
less setup-nvidia-cdi.sh
bash setup-nvidia-cdi.sh
claude-sandbox --recreate --gpu shell
nvidia-smi
```

From a checkout, run `bash container/setup-nvidia-cdi.sh` instead. For an
unmerged version, replace `main` in the download URL with its commit SHA.
Ask an agent to run `nvidia-smi` too, to check both isolation layers.

The helper requires Podman with `--cdi-spec-dir` support. Older versions,
including upstream 4.9, need an administrator to run from a host checkout:

```bash
sudo bash container/setup-nvidia-cdi.sh --system
```

Then retry the launcher as your normal user. Recreation alone cannot fix an
undiscoverable CDI specification. The helper installs no packages and grants
no device permissions; missing tools or permissions need your administrator.

User setup writes `~/.config/cdi/claude-sandbox-nvidia.yaml` and
`~/.config/containers/containers.conf.d/90-claude-sandbox-nvidia-cdi.conf`
(or under `$XDG_CONFIG_HOME`). It retains standard CDI search directories,
refuses to overwrite unmanaged files, and preserves the previous setup on
failure. Reconcile any custom `cdi_spec_dirs` setting with the drop-in.
Regenerate the specification after driver or GPU configuration changes.

## GPU devcontainers

The sandbox CDI class omits NVIDIA's params overlay so the agent can mount
fresh procfs for CUDA thread lookups; the standard `nvidia.com/gpu` class is
unchanged. The host launcher configures this automatically with `--gpu`.
For your own rootless Podman devcontainer, merge:

```json
"runArgs": [
  "--device=/dev/net/tun",
  "--device=nvidia.com/sandbox-gpu=all",
  "--security-opt=unmask=/proc/*"
],
"containerEnv": {
  "CLAUDE_SANDBOX_GPU": "1"
}
```

Rebuild to apply these settings. The agent wrapper restores sensitive proc
masks inside its own PID namespace. Non-GPU devcontainers need none of these
GPU additions. See [the procfs view](../explanations/sandbox-internals.md#the-procfs-view).

This beta targets rootless Podman. CUDA has been tested on the workstation;
RHEL8 and the VS Code devcontainer path still need live validation.
