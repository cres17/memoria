#!/usr/bin/env python3
"""Mandatory native GPU integration, with bounded simulator startup recovery."""
import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
from pathlib import Path



def boot(device, restart=False):
    if restart:
        subprocess.run(["xcrun", "simctl", "shutdown", device["udid"]], check=False, timeout=60)
    if restart or device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", device["udid"]], check=True, timeout=120)
    subprocess.run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], check=True, timeout=600)


def run_test(device, attempt, command=None, startup_timeout=180, process_timeout=1200, log_dir=Path("build")):
    # A compiled app sometimes never starts on a freshly migrated CI simulator.
    # Retry only that startup condition, never pixel assertions/performance failures.
    state = {"built_at": None, "started": False, "startup_timeout": False}
    completed = threading.Event()
    command = command or ["flutter", "test", "--verbose", "--no-pub",
               "integration_test/ios_gpu_ops_test.dart", "-d", device["udid"],
               "--reporter", "expanded"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    began = time.monotonic()

    def watchdog():
        while not completed.wait(1):
            startup_expired = (state["built_at"] is not None and not state["started"]
                               and time.monotonic() - state["built_at"] > startup_timeout)
            if startup_expired or time.monotonic() - began > process_timeout:
                state["startup_timeout"] = startup_expired
                print("GPU harness timeout: " + ("simulator app startup" if startup_expired else "whole test process"), flush=True)
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                return

    threading.Thread(target=watchdog, daemon=True).start()
    path = log_dir / "ios-gpu-integration.log"
    try:
        with path.open("w", buffering=1) as log:
            for line in process.stdout:
                if "Xcode build done." in line:
                    state["built_at"] = time.monotonic()
                if re.search(r"\d+:\d+ \+0: iOS Metal parity", line):
                    state["started"] = True
                print(line, end="", flush=True)
                log.write(line)
        result = process.wait()
    finally:
        completed.set()
        process.stdout.close()
        shutil.copyfile(path, log_dir / f"ios-gpu-integration.attempt-{attempt}.log")
    return result, state["startup_timeout"]



def main():
    subprocess.run(["python3", "tool/prepare_gpu_test_photos.py"], check=True)
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], timeout=90))
    phones = [dict(d, runtime=runtime) for runtime, devices in inventory["devices"].items()
              if "iOS" in runtime for d in devices
              if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not phones:
        raise SystemExit("No available iPhone simulator; GPU validation cannot be skipped")
    latest = max((p["runtime"] for p in phones), key=lambda r: tuple(map(int, re.findall(r"\d+", r))))
    phones = [p for p in phones if p["runtime"] == latest]
    device = next((p for p in phones if p["state"] == "Booted"), phones[-1])
    Path("build").mkdir(exist_ok=True)
    host = {"os": subprocess.check_output(["sw_vers"], text=True, timeout=15).strip(),
            "chip": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True, timeout=15).strip(),
            "simulator": device}
    Path("build/ios-gpu-host.json").write_text(json.dumps(host, indent=2) + "\n")
    print(f"GPU simulator: {device['runtime']} / {device['name']}", flush=True)

    for attempt in (1, 2):
        boot(device, restart=attempt > 1)
        result, startup_timeout = run_test(device, attempt)
        if not result:
            subprocess.run(["python3", "scripts/check_gpu_perf.py", "build/ios-gpu-integration.log"], check=True)
            break
        if attempt == 1 and startup_timeout:
            print("Retrying once after simulator app failed to start; acceptance limits unchanged", flush=True)
            continue
        raise SystemExit(result)


if __name__ == "__main__":
    main()
