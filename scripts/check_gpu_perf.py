#!/usr/bin/env python3
"""Extract measured GPU_EXPORT events; reject missing/CPU-fallback evidence.

Timing limits are based on a recorded simulator app-path baseline, never the
M5 native kernel microbenchmark. GPU error fallback cannot pass the gate.
"""
import json
import sys
from pathlib import Path

rows = []
pixel_comparisons = []
reference_comparisons = []
preview_timings = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if "GPU_EXPORT " in line:
        rows.append(json.loads(line.split("GPU_EXPORT ", 1)[1]))
    if "GPU_DIFF " in line:
        pixel_comparisons.append(json.loads(line.split("GPU_DIFF ", 1)[1]))
    if "GPU_REFERENCE" in line:
        reference_comparisons.append(line[line.index("GPU_REFERENCE"):])
    if "GPU_PREVIEW " in line:
        preview_timings.append(json.loads(line.split("GPU_PREVIEW ", 1)[1]))
if {r["gpu"] for r in rows} != {False, True}:
    raise SystemExit("Missing CPU/GPU full-export timing")
expected_previews = {(edge, complex_recipe, gpu) for edge in (320, 720)
                     for complex_recipe in (False, True) for gpu in (False, True)}
if {(r["long_edge"], r["complex"], r["gpu"]) for r in preview_timings} != expected_previews:
    raise SystemExit("Missing CPU/GPU preview timing pairs")
if any(len(r["samples_ms"]) != 3 for r in preview_timings):
    raise SystemExit("Preview timing requires three samples per mode")
for row in rows:
    phases = {t.get("phase") for t in row["timings"]}
    if not {"read_decode_orientation", "spatial_visual_pipeline", "encode_write"} <= phases:
        raise SystemExit("Missing export phase timing")
    if row["gpu"] and ("gpu_fallback" in phases or not any(t.get("op") == "noise" for t in row["timings"])):
        raise SystemExit("Native GPU path was not exercised")
budget = json.loads(Path("ci/perf_budgets.json").read_text())["_gpu_ops_ios"]
limit = budget.get("enforced_ms")
gpu_export = next(row for row in rows if row["gpu"])
if limit is not None and gpu_export["total_ms"] > limit:
    raise SystemExit(f"GPU full export {gpu_export['total_ms']}ms exceeds {limit}ms simulator budget")
target = Path("build/ios-gpu-export.json")
host_file = Path("build/ios-gpu-host.json")
target.write_text(json.dumps({"environment": "iOS Simulator host GPU", "exports": rows,
    "pixel_comparisons": pixel_comparisons, "reference_comparisons": reference_comparisons,
    "preview_timings": preview_timings,
    "host": json.loads(host_file.read_text()) if host_file.exists() else None,
    "budget_ms": limit}, indent=2) + "\n")
print(f"Saved measured app-path timings: {target}")
