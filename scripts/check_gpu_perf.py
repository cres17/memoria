#!/usr/bin/env python3
"""Extract measured GPU_EXPORT events; reject missing/CPU-fallback evidence.

Initial CI is observational. Timing limits are enabled only after recording a
successful simulator baseline; no M5 kernel value becomes an app-path budget.
"""
import json
import sys
from pathlib import Path

rows = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if "GPU_EXPORT " in line:
        rows.append(json.loads(line.split("GPU_EXPORT ", 1)[1]))
if {r["gpu"] for r in rows} != {False, True}:
    raise SystemExit("Missing CPU/GPU full-export timing")
for row in rows:
    phases = {t.get("phase") for t in row["timings"]}
    if not {"read_decode_orientation", "spatial_visual_pipeline", "encode_write"} <= phases:
        raise SystemExit("Missing export phase timing")
    if row["gpu"] and ("gpu_fallback" in phases or not any(t.get("op") == "noise" for t in row["timings"])):
        raise SystemExit("Native GPU path was not exercised")
target = Path("build/ios-gpu-export.json")
target.write_text(json.dumps({"environment": "iOS Simulator host GPU", "exports": rows}, indent=2) + "\n")
print(f"Saved measured app-path timings: {target}")
