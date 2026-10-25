# iOS GPU operations

Base: `f566062807ee7458966dd1ac5be2b635de7e63e0` (`feat/platform-hardening-2`).
Implementation lives in a separate checkout; the existing dirty app checkout
and `~/workspace/memoria-gpu-bench/cpu/lib/*.dart` were not edited.

## Decisions and behavior

- D1: primitive RGB channel tolerance is NR maximum absolute difference ≤1,
  Gaussian blur ≤2. These are acceptance limits, not proven universal bounds.
- D2: NR uses `fast::pow/exp` and fast math; blur is separately compiled with
  `-fno-fast-math`. The kernels are built into `default.metallib`; no runtime
  source compilation is used.
- D3: iOS only. Android/web execute CPU operations without native GPU calls.
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

CPU goldens and reference PNGs are retained. A failed or malformed native reply
uses the CPU implementation. If any GPU operation fails during visual rendering,
the entire visual recipe is rerun from its original input on CPU, avoiding a
mixture of earlier approximate GPU results and later CPU results.

## Memory and pixel contracts

At 3012×4016, one float4 Lab buffer occupies 193,539,072 bytes. Two full buffers
would occupy 387,078,144 bytes (369.15 MiB), before input/output and Dart images.
NR instead uses 256-row tiles with up to three halo rows on either side. Tile
boundaries retain the original neighborhood samples; only interior rows are
copied to output. Native requests are serialized and checked against buffer
limits and one quarter of physical memory before scratch allocation. This is a
conservative guard, not a measured iPhone peak-memory guarantee.

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

The iOS integration test uses both committed source photos and the five existing
visual references. `tool/prepare_gpu_test_photos.py` embeds them into a generated,
ignored Dart file imported only by the integration target; production Runner
does not bundle these additional test fixtures. Tests cover NR settings/detail,
RGBA, row-tile boundaries, blur radii, a real background-isolate native call,
existing reference tolerances, and the actual `EditorExportService`.

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

Primitive parity uses the two photos resized to width 320. Its RGBA channel
metrics include alpha; full-resolution 12MP native Mac evidence is separate.

## Verified locally / pending

- Existing CPU goldens and editor-renderer baseline tests passed after the shared
  operation refactor. The full suite passed 636 tests at that revision (one
  existing external-model case prints a skip message).
- Swift module compiled for macOS and typechecked against the iOS Simulator SDK.
- Precompiled native Mac module checked against the original 12MP CPU outputs:
  NR A/B max=1; blur r5 max=2; blur r20 max=1. This was a single native invocation
  per case including tiled allocation/copy work, not the original benchmark's
  warm median and not an iOS MethodChannel measurement.
- iOS GPU integration CI passed at `88e219c`: 16 primitive comparisons, real
  background channels, five app-asset CPU/GPU comparisons, five legacy reference
  comparisons and complete export service timing. [Run](https://github.com/cres17/memoria/actions/runs/40166810087).
- Local Xcode Metal asset discovery failed despite downloading the component.
  The Apple toolchain image was mounted read-only to compile and validate the
  native Mac module. Local Runner simulator build failed before app compilation: CoreSimulator
  1171.7.0 is older than Xcode build 1174.9.2; Flutter framework preparation
  also rejected the combined architecture string. Remote CI is checked
  separately; no iPhone result is claimed here.

Native Mac check (with an available Metal compiler):

```sh
mkdir -p build/gpu-native
xcrun -sdk macosx metal -ffast-math -c ios/Runner/GpuNoise.metal -o build/gpu-native/noise.air
xcrun -sdk macosx metal -fno-fast-math -c ios/Runner/GpuBlur.metal -o build/gpu-native/blur.air
xcrun metallib build/gpu-native/noise.air build/gpu-native/blur.air -o build/gpu-native/default.metallib
xcrun swiftc -O ios/Runner/GpuOps.swift tool/check_gpu_native.swift -o build/gpu-native/check
build/gpu-native/check build/gpu-native/default.metallib ~/workspace/memoria-gpu-bench/out
```
