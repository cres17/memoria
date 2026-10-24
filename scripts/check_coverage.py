#!/usr/bin/env python3
"""lcov.info 의 줄 커버리지가 하한 이상인지 확인한다. 하한 미만이면 실패한다.

주의: lcov 는 테스트가 한 번이라도 불러온 파일만 포함한다. 한 번도 불러오지 않은 파일은
분모에 들어가지 않으므로 실제 전체 커버리지보다 높게 나온다.
"""
import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lcov")
    parser.add_argument("--min", type=float, required=True)
    args = parser.parse_args()

    total = hit = 0
    for line in open(args.lcov):
        if line.startswith("DA:"):
            total += 1
            if int(line.split(",")[1]) > 0:
                hit += 1
    if total == 0:
        print("no coverage data")
        return 1
    pct = 100.0 * hit / total
    print(f"line coverage {pct:.1f}% ({hit}/{total}), minimum {args.min:.1f}%")
    return 0 if pct >= args.min else 1


if __name__ == "__main__":
    sys.exit(main())
