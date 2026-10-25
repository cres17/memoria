#!/usr/bin/env python3
"""통합 테스트 로그의 `DEVICE_PERF name=ms` 줄을 예산 파일과 비교한다.

예산에 있는 항목이 로그에 없으면 실패한다(측정이 조용히 사라지는 것을 막기 위해).
`--optional name` 으로 해당 플랫폼에서 측정되지 않는 항목을 지정할 수 있다.
"""
import argparse
import json
import re
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("budgets")
    parser.add_argument("--optional", action="append", default=[])
    args = parser.parse_args()

    budgets = {k: v for k, v in json.load(open(args.budgets)).items() if not k.startswith("_")}
    measured = {}
    for line in open(args.log, errors="replace"):
        m = re.search(r"DEVICE_PERF (\w+)=(\d+)", line)
        if m:
            measured[m.group(1)] = int(m.group(2))

    failed = False
    print(f"{'metric':28s} {'ms':>8s} {'budget':>8s}")
    for name, limit in budgets.items():
        value = measured.get(name)
        if value is None:
            if name in args.optional:
                print(f"{name:28s} {'-':>8s} {limit:8d}  (skipped on this platform)")
                continue
            print(f"{name:28s} {'MISSING':>8s} {limit:8d}  FAIL")
            failed = True
            continue
        status = "ok" if value <= limit else "OVER BUDGET"
        failed |= value > limit
        print(f"{name:28s} {value:8d} {limit:8d}  {status}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
