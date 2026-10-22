# FFmpeg container — design sheet

Specification 1.1 • 22 October 2026 • Proposed implementation contract

## Purpose and boundary

A portable Alpine Linux service accepts uploaded media plus a validated operation, runs FFmpeg or FFprobe, and exposes an authenticated status page and downloadable result. It has no database, durable media storage, social credentials, or public port.

This sheet defines deployment and execution. The request contract is in **03_FFmpeg_API_Specification.md**. PostgreSQL already exists and is outside this container's deployment scope.

## Component decisions

| Component | Decision |
|---|---|
| Base | Supported Alpine release, pinned by image digest at implementation |
| API | Go standard-library HTTP server, compiled in a separate build stage |
| Sandbox launcher | Small static Go helper that confines itself, then execs FFmpeg/FFprobe (see Execution) |
| Processing | Patched FFmpeg and FFprobe packages; record exact versions and codecs in release manifest |
| Listener | HTTP on 8080, private media network only |
| Registry | Bounded in-memory jobs and idempotency records |
| Scratch | Dedicated size-limited tmpfs at /work |
| Durable state | None; caller owns recovery and persistence |
| Packaging | Independent repository and versioned OCI image; amd64 and arm64 when tested |

Do not inherit unverified Alpine or FFmpeg version numbers from earlier discussion. Lock supported versions when building, scan dependencies, and rebuild for security fixes. Codec availability is checked at startup and in CI. No runtime package downloads.

## Network contract

| Initiator | Destination | Rule |
|---|---|---|
| Rails worker | Media API TCP 8080 | Allow new connections and responses |
| FFmpeg service | Rails, database, Internet, host services | Deny new connections |
| FFmpeg subprocess | Any network socket | Deny through tested subprocess confinement |
| External proxy/browser | Media API | No route or published port |

Use a dedicated internal bridge with only the worker and media service attached. A bridge alone does not enforce one-way access: peers and host access need explicit host-managed firewall policy, including IPv6. Permit established return traffic; deny new connections originating from the media service. Validate rules after Docker/network recreation. Do not grant this container NET_ADMIN to manage its own policy.

The worker also joins the database and outbound API networks. It must not forward packets or expose a generic HTTP proxy. Its media-facing interface has no application listener. If several applications reuse the service, each gets a distinct API identity; shared network peers remain an explicit trust boundary.

## Execution and filesystem boundary

1. Authenticate and reserve capacity before consuming a large request.
2. Stream into a service-generated private directory. Disregard client filenames for filesystem paths.
3. Inspect with constrained FFprobe, validate media limits, and build arguments from a versioned operation allowlist.
4. Execute directly without a shell, through the sandbox launcher. Never accept raw flags, filter graphs, paths, URLs or script files.
5. Read input from the job's tmpfs file and write output to a seekable tmpfs file. Media is not piped through stdin/stdout: the input is already stored for hashing, and MP4/M4A output is written with `-movflags +faststart` so the index precedes the media data, which needs a seekable output.
6. Validate result size, format and checksum; publish it atomically in the job registry and shrink the job's storage reservation to the actual output size.
7. Retain successful output until explicit DELETE or TTL expiry. Delete input after execution. Failures retain sanitized metadata, not media files.

### Subprocess confinement

Protocol allowlists constrain FFmpeg input protocols but do not isolate local files. Every FFmpeg and FFprobe invocation goes through the sandbox launcher, which applies these controls to itself and then calls `execve`, so they persist into FFmpeg:

| Control | Mechanism |
|---|---|
| Filesystem | Landlock ruleset: read/execute only the FFmpeg binaries and their libraries; read the job's input file; read/write only the job's output directory. Everything else, including API secrets, other jobs and `/proc` of the API process, is denied. |
| Network | seccomp-bpf filter that fails `socket`, `socketpair`, `connect`, `bind` and `listen` with EPERM (FFmpeg needs no sockets for local files). Where the kernel supports Landlock network rules (ABI 4 or later), also deny TCP bind/connect there. |
| Resources | rlimits for address space, file size (output maximum), CPU time and open files, set before exec. |
| Process | New process group, `PR_SET_PDEATHSIG`, empty environment apart from a fixed allowlist; API keys are never in the environment or arguments. |

Namespace-based tools (bubblewrap, nsjail) are not the default: with capabilities dropped they need unprivileged user namespaces, which Docker's default seccomp profile normally blocks. Landlock and seccomp work unprivileged under `no-new-privileges`. They require a kernel with Landlock enabled (5.13 or later; network rules need 6.7 or later) and a container seccomp profile that permits the `landlock_*` syscalls. Verify both on the target host; use a custom seccomp profile if the default one does not allow them.

Sandbox implementation is a release gate. At startup, and in readiness checks, the launcher runs a self-test: a confined probe must fail to read the API key file, fail to open another job's directory and fail to create a socket. If the self-test cannot run or any check succeeds, fail readiness; never silently run unrestricted. A same-UID directory and protocol allowlist alone are insufficient. A separate stronger runtime such as gVisor can be an additional deployment layer, but is not assumed available.

## Resource budget

These are adjustable starting limits, not measured performance claims. The processing multipliers in particular must be measured on the target host before release.

| Setting | Default |
|---|---:|
| API port | 8080 |
| Upload maximum | 256 MiB |
| Output maximum | 256 MiB |
| Decoded image/frame maximum | 16,777,216 pixels |
| Maximum duration | 600 seconds |
| Probe timeout | 30 seconds |
| Processing timeout, base | 60 seconds |
| Processing timeout, per media second (transcode, trim, extract_audio) | 1.5 seconds |
| Processing timeout, per media second (remux) | 0.2 seconds |
| Processing timeout, ceiling | 1,200 seconds |
| Upload deadline | 120 seconds |
| Concurrent processing jobs | 1 |
| Accepted jobs with retained files | 3 total, including uploads, queued, processing and completed jobs |
| tmpfs ceiling | 1,024 MiB |
| Admission storage budget | 768 MiB |
| Container memory / CPU / PIDs | 2 GiB / 2 CPU / 128 |
| Output retention | 900 seconds after completion |
| Tombstone retention | 900 seconds after deletion or expiry |

### Processing timeout

The probe runs under its own 30-second timeout. After probing, each job's processing timeout is:

`min(ceiling, base + per_media_second × probed_duration)`

Still-image operations (resize), thumbnail and metadata use the base only. With the defaults, a 600-second video transcode gets 960 seconds. Benchmark the real-time factor of the chosen presets at the largest allowed output size on the target CPUs, and set the per-second multiplier with headroom. A job that exceeds its timeout fails with `processing_timeout`; the process group is killed and reaped.

### Admission and reservations

At admission, reserve the declared input size plus the output maximum. When a job completes, shrink its reservation to the actual output size; when it fails or is cancelled, release it entirely. Examples with the defaults:

- A maximum-size upload (256 MiB + 256 MiB = 512 MiB) can run while one small completed output awaits download, but not alongside another maximum-size job.
- Typical inputs (for example 20 MiB + 256 MiB) allow a queued job behind a processing one.

Reject excess work with 503 and Retry-After rather than promise queue capacity. tmpfs and processing memory both consume the container's memory allowance. Capacity reservation, actual bytes written, output monitoring, and subprocess memory limits must work together. Bound threads, probe bytes, stderr capture, HTTP headers, concurrent uploads, and job metadata. Keep at most 1,000 metadata/tombstone records; reject admission if the bounded registry is exhausted.

Completed outputs that are never downloaded keep their (shrunk) reservation until DELETE or expiry. The Rails worker is responsible for deleting orphaned jobs on restart (see 02_Rails_Container_Design.md).

## Container deployment requirements

| Control | Requirement |
|---|---|
| Identity | Non-root UID/GID 10001 |
| Root filesystem | Read-only; only /work writable |
| Capabilities | Drop ALL; no-new-privileges |
| Seccomp | Profile that permits `landlock_*` syscalls; verified at release |
| Mounts | /work tmpfs with nosuid,nodev,noexec; API secret read-only |
| Secrets | Separate key per consumer; support overlap during rotation |
| Privilege | No Docker socket, host PID/network namespace, device mounts or privileged mode |
| Logging | Structured stdout; bounded retention outside container |
| Restart | Restart unless stopped; clean /work before listening |
| Health | /health/live for process; /health/ready for binaries, sandbox self-test and writable scratch |
| Shutdown | Stop accepting jobs, allow bounded drain, then terminate process groups, mark unfinished jobs cancelled and clean scratch |

No PostgreSQL service or volume is included. Runtime secrets are provisioned by the operator and not baked into images. Do not promise RAM never reaches disk: tmpfs may use host swap; configure disabled or encrypted swap when that guarantee is required.

## Configuration interface

`HTTP_ADDR`, `API_KEYS_FILE`, `WORK_DIR`, `MAX_UPLOAD_BYTES`, `MAX_OUTPUT_BYTES`, `MAX_DURATION_SECONDS`, `MAX_PIXELS`, `MAX_CONCURRENT_JOBS`, `MAX_RETAINED_JOBS`, `STORAGE_BUDGET_BYTES`, `PROBE_TIMEOUT_SECONDS`, `PROCESS_TIMEOUT_BASE_SECONDS`, `PROCESS_TIMEOUT_PER_MEDIA_SECOND_ENCODE`, `PROCESS_TIMEOUT_PER_MEDIA_SECOND_REMUX`, `PROCESS_TIMEOUT_MAX_SECONDS`, `UPLOAD_TIMEOUT_SECONDS`, `JOB_TTL_SECONDS`, `TOMBSTONE_TTL_SECONDS`, `LOG_LEVEL`.

Validate values and the resource budget on startup: `STORAGE_BUDGET_BYTES` must be at least `MAX_UPLOAD_BYTES + MAX_OUTPUT_BYTES` and no more than the tmpfs ceiling, and the timeout ceiling must be at least `base + per_media_second × MAX_DURATION_SECONDS` for encode operations. Docker supplies memory/CPU/tmpfs limits separately. An invalid configuration fails startup.

## Recovery and acceptance

The service generates a boot instance identifier. All registry data is lost on restart; unknown job IDs then return 404. Rails retains source media and processing intent in PostgreSQL and may resubmit processing safely. A partially downloaded output is never committed as a ready asset.

Release gates:

- Actual-file transcode, thumbnail, probe and audio tests on both supported architectures.
- A maximum-duration transcode at the largest allowed size completes within its computed timeout on the target CPUs.
- MP4 and M4A outputs have the index before the media data.
- Malformed input, truncated body, traversal, external references, unknown parameters and MIME mismatch rejected.
- Prove subprocesses cannot read API secrets or another job, create sockets, or reach PostgreSQL/host/Internet; the readiness self-test fails when confinement is unavailable.
- Timeouts kill and reap the whole process group; cancellation is safe during upload, execution and download.
- Saturation returns controlled errors; reservations shrink on completion and release on failure; memory/size limits hold under adversarial fixtures.
- Repeat downloads work; successful GET does not delete output. Explicit deletion and expiry clean resources.
- Restart loses ephemeral jobs predictably; build produces SBOM and vulnerability scan results.

## References

- [Docker bridge networking](https://docs.docker.com/engine/network/drivers/bridge/) — shared bridge reachability.
- [Docker firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/) — host network enforcement.
- [Docker seccomp profiles](https://docs.docker.com/engine/security/seccomp/) — default profile and custom profiles.
- [Linux Landlock](https://docs.kernel.org/userspace-api/landlock.html) — unprivileged filesystem and network restrictions.
- [FFmpeg protocols](https://ffmpeg.org/ffmpeg-protocols.html) — protocol controls and pipe behavior.

All numeric limits, endpoints and confinement gates above are design requirements for this project.

## Changes in 1.1

- Replaced the fixed 120-second processing timeout with a separate probe timeout and a duration-scaled processing timeout.
- Reservations now shrink to actual output size on completion; retained-job limit raised to 3; startup validates budget consistency.
- Specified the sandbox: Landlock plus seccomp through a launcher, with a readiness self-test; explained why namespace tools are not the default.
- Removed stdin/stdout media piping; MP4/M4A outputs use faststart.
- Shutdown marks unfinished jobs cancelled; added related release gates.
