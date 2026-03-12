# Integrating Roar with OSMO Job Launches

## Background

**Goal:** When OSMO launches jobs, wrap them with `roar run` so that file I/O
provenance is captured automatically. The integration should be YAML-config-only
(no OSMO source changes) and ideally affect all launched jobs globally.

## How OSMO Launches Jobs

OSMO runs each task in a Kubernetes pod with three containers:

1. **osmo-init** (init container) -- sets up shared volumes, installs binaries
2. **osmo-ctrl** -- manages data transfer, coordinates execution
3. **user container** -- runs the user's actual workload

The user container's entrypoint is always `/osmo/bin/osmo_exec`, which receives the
real command/args and calls `exec.Command(args[0], args[1:]...)` directly.

Key details:
- `/osmo/usr/bin` is a shared EmptyDir volume written by init, mounted **read-only**
  in the user container
- `osmo_exec` **appends** `/osmo/usr/bin` to PATH (not prepends), so binaries there
  won't override system commands like `python` or `bash`
- Pod templates are the global config mechanism: `osmo config update POD_TEMPLATE`
- Pod templates merge by `name` field -- new init containers are appended, existing
  ones are merged recursively

## Options

### Option A: Per-Task Command Wrapping (simplest, not global)

Change each task's command in the workflow YAML:

```yaml
# Before
tasks:
  - name: train
    image: my-image:latest
    command: ["python"]
    args: ["train.py", "--epochs", "10"]

# After
tasks:
  - name: train
    image: my-image:latest
    command: ["roar", "run", "python"]
    args: ["train.py", "--epochs", "10"]
```

**Requires:** `roar` installed in the container image.

**Pros:** Dead simple, no infrastructure changes.
**Cons:** Per-task, not global. Every workflow YAML must be edited. Easy to forget.

---

### Option B: Pod Template Init Container + PATH Prepend (recommended, global)

Use a pod template to add a custom init container that:
1. Installs `roar` into a shared volume
2. Creates wrapper scripts for common commands (python, bash, etc.)

Then use the pod template to set an environment variable on the user container that
causes the wrapper directory to be found first in PATH.

#### How it works

`osmo_exec` sets PATH like this (user.go:341):
```go
os.Setenv("PATH", fmt.Sprintf("%s:%s", os.Getenv("PATH"), cmdArgs.UserBinPath))
```

This takes the container's existing PATH and appends `/osmo/usr/bin`. If we inject
a directory at the **front** of the container's PATH via a pod template env var,
our wrappers will take precedence over system binaries.

#### Pod template

```json
{
  "spec": {
    "volumes": [
      {
        "name": "roar-wrappers",
        "emptyDir": {}
      }
    ],
    "initContainers": [
      {
        "name": "roar-init",
        "image": "python:3.12-slim",
        "command": ["sh", "-c"],
        "args": [
          "pip install --quiet roar-cli && ROAR_BIN=$(which roar) && cp \"$ROAR_BIN\" /roar-bin/roar && for cmd in python python3 bash sh; do printf '#!/bin/sh\\nexec /roar-bin/roar run %s \"$@\"\\n' \"$(which $cmd)\" > /roar-bin/$cmd && chmod +x /roar-bin/$cmd; done && cp \"$ROAR_BIN\" /roar-bin/roar"
        ],
        "volumeMounts": [
          {
            "name": "roar-wrappers",
            "mountPath": "/roar-bin"
          }
        ]
      }
    ],
    "containers": [
      {
        "name": "{{USER_CONTAINER_NAME}}",
        "env": [
          {
            "name": "ROAR_WRAPPER_DIR",
            "value": "/roar-bin"
          }
        ],
        "volumeMounts": [
          {
            "name": "roar-wrappers",
            "mountPath": "/roar-bin",
            "readOnly": true
          }
        ]
      }
    ]
  }
}
```

**Challenge:** Setting PATH via Kubernetes env vars replaces the entire value --
there's no `$(PATH)` expansion in K8s pod specs. The user container image's
default PATH would be lost.

**Workaround options:**
1. Hardcode a known PATH: `PATH=/roar-bin:/usr/local/bin:/usr/bin:/bin` -- fragile
   if images have non-standard paths.
2. Use the init container to write a shell profile snippet (e.g.,
   `/roar-bin/roar-profile.sh` with `export PATH=/roar-bin:$PATH`), and rely on
   bash sourcing it. But this only works for interactive/bash commands.
3. Have the init container write wrapper scripts that use **absolute paths** for
   the real binary, discovered at init time from the user image. Requires the init
   container to share the user image's filesystem or know the paths in advance.

**Pros:** Truly global via pod template. All jobs get roar wrappers automatically.
**Cons:** PATH manipulation is fragile across different base images. Wrapper scripts
must enumerate commands to wrap. Init container adds startup latency.

---

### Option C: Custom Base Image with Roar (global via image convention)

Build a custom base image layer that:
1. Installs `roar-cli`
2. Runs `roar init` in a standard location
3. Provides a custom entrypoint wrapper

```dockerfile
FROM my-base-image:latest
RUN pip install roar-cli
COPY roar-entrypoint.sh /usr/local/bin/roar-entrypoint.sh
```

Where `roar-entrypoint.sh` is:
```bash
#!/bin/bash
roar init -y 2>/dev/null || true
exec roar run "$@"
```

Users set their workflow YAML to use the roar-enabled image and set
`command: ["/usr/local/bin/roar-entrypoint.sh", "python"]`.

**Pros:** Clean, self-contained, works with any command.
**Cons:** Requires building/maintaining custom images. Per-image, not per-cluster.

---

### Option D: LD_PRELOAD with Roar's Preload Tracer (global, partial)

Roar includes a `roar-tracer-preload` shared library that uses `LD_PRELOAD` to
intercept file I/O syscalls. This can be set globally via pod template:

```json
{
  "spec": {
    "containers": [
      {
        "name": "{{USER_CONTAINER_NAME}}",
        "env": [
          {
            "name": "LD_PRELOAD",
            "value": "/roar-lib/libroar_tracer_preload.so"
          }
        ],
        "volumeMounts": [
          {
            "name": "roar-wrappers",
            "mountPath": "/roar-lib",
            "readOnly": true
          }
        ]
      }
    ]
  }
}
```

Combined with an init container that copies the preload library into the shared volume.

**Pros:** Truly transparent -- no command wrapping needed. Captures all file I/O
from any process.
**Cons:** Only captures the tracing part of roar (file I/O observation), not the full
`roar run` experience (git context, session management, DAG tracking, GLaaS
registration). Also, LD_PRELOAD can interfere with some binaries (static binaries,
setuid programs).

## Recommendation

**Option B (pod template init container)** is the closest to the requirements:
global, YAML-only, no OSMO source changes. The main challenge is PATH manipulation
across heterogeneous base images.

A practical hybrid is:

1. Use **Option B's init container** to install roar + wrapper scripts into a shared volume
2. Use **Option A's command wrapping** as the per-task mechanism, but now it's trivial
   because roar is guaranteed to be available at a known path (`/roar-bin/roar`)
3. Provide a **workflow YAML template/convention** where `command` is set to
   `["/roar-bin/roar", "run", "<actual-command>"]`

This avoids the PATH fragility entirely. The pod template ensures roar is installed
in every pod; the workflow YAML just references it at its known absolute path.

## Open Questions

1. Should roar register results with GLaaS automatically, or just capture locally?
   If GLaaS, the pod template needs `GLAAS_URL` and auth credentials injected.
2. Should `roar init` run per-job or should there be a persistent `.roar` directory?
   For Kubernetes pods (ephemeral), per-job init is likely the right default.
3. Which commands need wrapping? Just `python`/`bash`, or everything? The init
   container's wrapper list needs to be comprehensive for Option B's PATH approach.
4. Does OSMO's `osmo_exec` binary interact well with roar's tracing? Since
   `osmo_exec` uses Go's `exec.Command` (which calls `execve`), roar's preload
   and ptrace backends should work. eBPF should also work if the pod has
   sufficient privileges.
