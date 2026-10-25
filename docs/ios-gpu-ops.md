# iOS GPU operations

Base: `f566062807ee7458966dd1ac5be2b635de7e63e0` (`feat/platform-hardening-2`).
The benchmark CPU implementation is an immutable reference. CPU goldens and
committed reference PNGs remain unchanged.

## Decisions and behavior

- D1: primitive RGB channel tolerance is NR maximum absolute difference ≤1,
  Gaussian blur ≤2. These are acceptance limits, not proven universal bounds.
- D2: NR uses `fast::pow/exp` and fast math; blur is separately compiled with
  `-fno-fast-math`. The kernels are built into `default.metallib`; no runtime
  source compilation is used.
- D3: iOS only. Android/web execute CPU operations without native GPU calls.
  Policy and root-isolate token are captured together only for enabled iOS
  requests. Chrome tests verify that Web never accesses its unsupported token API.
- D4: production preview and export share the same operation sequence. The
  existing synchronous CPU entry points remain available for numeric goldens.
  NR and convolutions inside HDR, glow, halation, details, artistic effects and
  tilt/lens blur are dispatched. The surrounding effect arithmetic remains Dart.
  RAW development and healing during spatial preparation remain CPU.
- D5: `enabled.gpu_ops_ios` in `config/remote_flags.json` defaults to **false**.
  A missing key or expired configuration disables it. Valid opt-in config is
  cached up to 14 days; refresh failures retain an unexpired last valid value.
  The effective expiry is checked at every render boundary. Existing refresh
  throttling is six hours, so a remote disable is **not an immediate guarantee**.
  A request freezes its flag at entry; a new setting applies to later requests.
  A persistent local operation guard can veto an opt-in even while offline.

CPU goldens and reference PNGs are retained. A failed or malformed native reply
uses the CPU implementation. If any GPU operation fails during visual rendering,
the partial attempt stops immediately and the entire visual recipe is rerun
from its original input on CPU. Foreground interruption instead cancels the
render, avoiding a long new CPU retry while the app is being deactivated.

## Operation admission, interruption and crash recovery

`gpuBegin` persists and synchronizes an active lease **before** Dart packs pixels.
`gpuEnd` clears it after output validation/unpacking. Only one lease is admitted;
another preview/export request uses CPU rather than waiting behind a serial GPU
queue. A stale end cannot release a newer lease.

On a subsequent process launch, an unfinished lease disables GPU operations for
the same app version/build. Timeouts and command failures also persist that
quarantine. It survives offline launches and remote opt-in; a different app
version/build resets it. Unreadable guard state fails closed. This is a
conservative interruption detector, not proof of a GPU-caused crash: force-quit,
OS termination or an isolate killed before cleanup can also leave a lease.
That false positive keeps the same build on CPU until an update.

`willResignActive` stops admission and invalidates an active lease. Every tile
and command submission checks it; returning to foreground cannot revive that
interrupted operation. `notPermitted` is treated as interruption even if the
notification raced. The export service raises the typed `systemInterrupted` failure and removes
partial output. The editor explains that no photo was saved and asks the user to
retry; if inactive, it defers this notice until resume. Explicit user cancellation
remains silent. Previews keep their existing image. No background-task time extension or
completion guarantee is claimed. Background **isolate** tests do not test app
background suspension; home/phone-call scenarios still require physical devices.

Native command completion has a 20-second deadline for the operation. Dart
channel admission/operation calls each have a 30-second timeout, with bounded
cleanup. These are recovery policy values, not measured latencies. A committed
Metal command cannot be cancelled by this code: a timed-out command may still
hold its retained buffers until the driver completes it. The build is quarantined
before a CPU retry; the implementation does not enqueue further GPU work.

2D groups use the pipeline execution width and a total-thread budget capped at
`min(256, maxTotalThreadsPerThreadgroup)`. Timing replies log each pipeline's
limit and chosen dimensions. Tests exercise limits below 256; the iPhone limits
remain to be measured. This follows Apple's [threadgroup guidance](https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes?changes=_5_6)
and [background guidance](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background?changes=_1_5).

## Memory and pixel contracts

At 3012×4016, one float4 Lab buffer occupies 193,539,072 bytes. Two full buffers
would occupy 387,078,144 bytes (369.15 MiB), before input/output and Dart images.
NR instead uses 256-row tiles with up to three halo rows on either side. Tile
boundaries retain the original neighborhood samples; only interior rows are
copied to output. Native requests are serialized and checked against buffer
limits and one quarter of physical memory before scratch allocation. This is a
conservative guard, not a measured iPhone peak-memory guarantee.
Dart sends the existing uint8 view instead of an extra full-image packing copy;
blur no longer allocates an unused full-image output before its final copy.
Codec copies, returned bytes, NR's RGB conversion and other Dart images remain.
An Instruments peak-memory/jetsam check is still required.

RGB and RGBA are supported. A 12MP RGBA transfer is 48,384,768 bytes each way.
Blur processes alpha as the CPU primitive does. NR keeps the existing RGB
intermediate contract; the pipeline restores exact source alpha at its boundary.
Small images with unsupported blur radii and non-uint8/palette/multiframe inputs
use CPU. Half precision is not used.
Physical iOS GPUs below Apple family 4 also use CPU before command encoding.

## Reproducible checks

```sh
flutter pub get --enforce-lockfile
python3 tool/prepare_gpu_test_photos.py
flutter test --no-pub
flutter analyze --no-fatal-infos
python3 scripts/run_ios_gpu_ci.py
```

The existing device workflow uses `scripts/run_device_tests.sh` to select all
original integration tests. The added iOS GPU test is excluded only from that
cross-platform list and is mandatory in the separate GPU CI job. This avoids
compiling its generated photo fixtures into Android tests or duplicating the
12MP performance run. `bash scripts/run_device_tests.sh --list` prints the list.
The GPU harness selects the newest available iOS runtime and flushes verbose
logs as they arrive. If a built simulator app does not start its test body within
180 seconds, it reboots that simulator and retries once. Pixel assertions, test
failures and performance-budget failures are not retried or relaxed. Both
attempt logs are retained. Host GPU information comes from native timing replies;
an extra `system_profiler` display query is not required on virtual CI hosts.

The iOS integration test uses both committed source photos and the five existing
visual references. `tool/prepare_gpu_test_photos.py` embeds them into a generated,
ignored Dart file imported only by the integration target; production Runner
does not bundle these additional test fixtures. Tests cover NR settings/detail,
RGBA, row-tile boundaries, blur radii, a real background-isolate native call,
existing reference tolerances, and the actual `EditorExportService`.
The review follow-up adds black, white, saturated primaries, a one-pixel
checkerboard and seeded noise (64×270 RGBA, crossing a tile boundary): 30 more
primitive comparisons. `GPU_PIPELINES` logs actual native limits. The Swift
guard check simulates process relaunch with an unfinished lease, corrupt state,
foreground interruption, timeout quarantine and a stale reply. These are
automated state/protocol checks, not physical lifecycle or driver-hang tests.

The first simulator run exposed an existing reference limitation: `film_look`
was generated in a plain unit-test environment where optional vintage textures
were not loaded. The integration test checks real bundled-asset CPU/GPU parity,
then separately reproduces that legacy asset-unavailable contract to compare the
unchanged PNG. It does not regenerate a golden or widen a tolerance to hide the
asset difference. The other reference cases use the normal app asset path.

`GPU_EXPORT` records one complete CPU and GPU export: isolate spawn, input file
read/decode/orientation, spatial/visual processing, encoding and file write.
Native telemetry separates summed GPU command-buffer time from native wall time;
the difference includes allocation, copying, submission and synchronization and
must not be labeled pure copy time. Dart telemetry records packing, unpacking,
round-trip wall time, blur copy-back time and byte count. `scripts/check_gpu_perf.py` rejects missing
measurements and CPU fallback, then saves `build/ios-gpu-export.json`.

The first successful simulator run at `88e219c` measured a complete 12MP export
(NR 100/100 + sharpen 20, JPEG quality 90) once per mode:

| Phase (ms) | CPU | GPU enabled |
|---|---:|---:|
| Complete service call | 22190.085 | 4724.602 |
| Read/decode/orientation | 718.073 | 611.292 |
| Spatial/visual pipeline | 20672.692 | 2780.454 |
| Encode/write | 788.303 | 823.114 |

The complete-call ratio is 4.697. These are debug integration-test timings on a
CI-host simulator, not iPhone results or AOT benchmark medians. The complete
service call includes worker startup and other overhead outside the phase timers.
`ci/perf_budgets.json` sets a **policy ceiling** of 14174ms (ceil of measured GPU
4724.602ms × 3 for shared-CI noise). That ceiling is not a measured runtime.
`scripts/check_gpu_perf.py` enforces it and preserves the raw timing payload.
Do not enable production before physical iPhone correctness, memory and
end-to-end latency checks.

At `8f47099`, another single debug CI sample measured CPU 39749.172ms and GPU
9676.236ms on Apple M1 (Virtual), macOS 26.6.2, iOS 26.5 simulator. These samples
show substantial host variation; neither the ratio nor the ceiling establishes
release/profile speed on an iPhone. Native pipelines were warmed by preceding
parity checks. No speedup for the remaining Dart stages is inferred by subtraction.

`GPU_PREVIEW` separately records three preview-worker samples and their median
after an explicit warm-up at long edges 320 and 720, for basic and compound
recipes. It includes isolate transfer and PNG encoding. A pixel-count cutoff is
not selected from debug host timings: profile-mode preview latency on physical
iPhones is still required before rollout.

Primitive parity uses the two photos resized to width 320. Its RGBA channel
metrics include alpha; full-resolution 12MP native Mac evidence is separate.

## Verified locally / pending

- Existing CPU goldens and editor-renderer baseline tests passed after the shared
  operation refactor. The full suite passed 636 tests at that revision (one
  existing external-model case prints a skip message).
- Swift module compiled for macOS and typechecked against the iOS Simulator SDK.
- Review follow-up: full local suite passed 643 tests (one VM skip), plus native
  guard persistence/dispatch-limit checks. M5 12MP comparison after dynamic
  groups retained NR A/B max=1, blur r5 max=2, r20 max=1.
- Precompiled native Mac module checked against the original 12MP CPU outputs:
  NR A/B max=1; blur r5 max=2; blur r20 max=1. This was a single native invocation
  per case including tiled allocation/copy work, not the original benchmark's
  warm median and not an iOS MethodChannel measurement.
- iOS GPU integration CI passed at `88e219c`: 16 primitive comparisons, real
  background channels, five app-asset CPU/GPU comparisons, five legacy reference
  comparisons and complete export service timing. [Run](https://github.com/cres17/memoria/actions/runs/40166810087).
- Physical validation remains HOLD: correctness, repeated profile/release
  exports, Instruments peak memory, background/interruption, thermal/low-power
  behavior and preview latency. The current opt-in defaults to off. Before any
  rollout, define a small explicit cohort/percentage with a stable installation
  assignment; no percentage policy is implemented by the current boolean flag.
- Repository administration remains separate: add the GPU job to required checks
  when applying branch protection and follow the dependency merge order. Commit
  identity/history and protection rules are not rewritten by this implementation.

Native Mac check (with an available Metal compiler):

```sh
mkdir -p build/gpu-native
xcrun -sdk macosx metal -ffast-math -c ios/Runner/GpuNoise.metal -o build/gpu-native/noise.air
xcrun -sdk macosx metal -fno-fast-math -c ios/Runner/GpuBlur.metal -o build/gpu-native/blur.air
xcrun metallib build/gpu-native/noise.air build/gpu-native/blur.air -o build/gpu-native/default.metallib
xcrun swiftc -O ios/Runner/GpuRequestGate.swift ios/Runner/GpuOps.swift tool/check_gpu_native.swift -o build/gpu-native/check
# Set BENCH_OUTPUT to the directory containing cpu.json and the reference RGBs.
build/gpu-native/check build/gpu-native/default.metallib "$BENCH_OUTPUT"
```

## Second review follow-up (2026-10-25)

- N1: system interruption is distinct from user cancellation through the export
  failure contract. It never triggers the lower-resolution or CPU retry. The
  notice is deferred while inactive so it does not expire before the user returns.
  The conservative `willResignActive` admission/invalidation policy is unchanged;
  notification/control center and phone interruptions still require device tests.
- N2: parity logs additionally record `mean_signed_gpu_minus_cpu`,
  `frac_gpu_darker`, and `frac_gpu_lighter` (RGBA channel values, including alpha).
  These diagnose direction without changing kernels, rounding, D1 limits, or
  reference images. Broad saturated highlights in real photos remain a required
  physical-device input; the synthetic white fixture does not replace them.
  Uniform-white r5 reached max 2 in the prior f7f8a2a simulator run, so the
  tolerance is an acceptance threshold, not a demonstrated universal bound.
- N3/N4: the existing optional timing sink now receives `phase: gpu_recovery`
  events with reasons `busy`, `timeout`, `interrupted`, `blocked`, `failed`,
  `invalid_reply`, or `cleanup_failed`. Count events by reason in device runs;
  an interruption event is cancellation, not a CPU fallback. These events contain
  no pixels, file paths, or lease IDs. No remote telemetry upload is enabled.
  Blocked admissions include `blocked_reason`: `unfinished_lease`, `timeout`,
  `command_error`, `cleanup_failed`, or `unknown`. The reason persists across
  launches with the quarantine; old state records without a reason remain valid.
  An unfinished lease does not prove a GPU crash. The same-build quarantine policy
  remains conservative; no repeated-crash threshold or OS-based reset was added.

Real-device rates, highlight accuracy, profile timing, memory peaks, rollout
cohorts, and repository-required checks remain unverified or unapplied. The
feature remains disabled by default.
