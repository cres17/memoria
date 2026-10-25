#!/usr/bin/env python3
"""Run mandatory native GPU integration on an available iPhone simulator."""
import json
import subprocess
from pathlib import Path

subprocess.run(["python3", "tool/prepare_gpu_test_photos.py"], check=True)
inventory = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "--json"], timeout=90))
phones = [dict(d, runtime=runtime) for runtime, devices in inventory["devices"].items() for d in devices
          if d.get("isAvailable") and "iPhone" in d["name"]]
if not phones:
    raise SystemExit("No available iPhone simulator; GPU validation cannot be skipped")
device = next((d for d in phones if d["state"] == "Booted"), phones[0])
if device["state"] != "Booted":
    subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True, timeout=120)
subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True, timeout=300)
Path("build").mkdir(exist_ok=True)
host = {"os": subprocess.check_output(["sw_vers"], text=True).strip(),
        "chip": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(),
        "gpu": subprocess.check_output(["system_profiler", "SPDisplaysDataType"], text=True, timeout=30).strip(),
        "simulator": device}
Path("build/ios-gpu-host.json").write_text(json.dumps(host, indent=2) + "\n")
with Path("build/ios-gpu-integration.log").open("w") as log:
    process = subprocess.Popen(["flutter", "test", "--no-pub", "integration_test/ios_gpu_ops_test.dart",
                                "-d", device["udid"], "--reporter", "expanded"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        print(line, end="", flush=True)
        log.write(line)
    result = process.wait()
if result:
    raise SystemExit(result)
subprocess.run(["python3", "scripts/check_gpu_perf.py", "build/ios-gpu-integration.log"], check=True)
