"""Audit legacy versus corrected Canon LUT composition using direct color values.

This audit never reads model predictions or the held-out test split.  It checks
the source-domain contract and compares matching CLog2/CLog3 look files on the
same sRGB cube before deciding whether Canon-derived training samples are safe.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import re
from pathlib import Path

import numpy as np

from canon_color_contract import SRGB_TO_CINEMA_GAMUT


generator = importlib.import_module("2_generate_dataset")
evaluator = importlib.import_module("17_evaluate_conditional_lut")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def legacy_srgb_to_canon_log(values: np.ndarray, log_version: str) -> np.ndarray:
    """Reproduce the axis-v2 transfer-only implementation for comparison."""
    linear = np.where(
        values <= 0.04045,
        values / 12.92,
        ((values + 0.055) / 1.055) ** 2.4,
    )
    if log_version == "canon_clog2":
        encoded = 0.529136 * np.log10(10.1596 * linear + 1.0) + 0.0730597
    elif log_version == "canon_clog3":
        encoded = 0.42889912 * np.log10(14.98325 * linear + 1.0) + 0.12783901
    else:
        raise ValueError(log_version)
    return np.clip(encoded, 0.0, 1.0).astype(np.float32)


def compose(lut: np.ndarray, version: str, *, legacy: bool) -> np.ndarray:
    coords = np.linspace(0.0, 1.0, generator.LUT_DIM, dtype=np.float32)
    red, green, blue = np.meshgrid(coords, coords, coords, indexing="ij")
    srgb = np.stack((red, green, blue), axis=-1)
    canon_input = (
        legacy_srgb_to_canon_log(srgb, version)
        if legacy
        else generator.srgb_to_canon_log(srgb, version)
    )
    return generator.apply_lut_to_colors(canon_input, lut).astype(np.float32)


def delta_e(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    return evaluator.delta_e2000(
        evaluator.rgb_to_lab(left),
        evaluator.rgb_to_lab(right),
    )


def comparison(left: np.ndarray, right: np.ndarray) -> dict:
    differences = delta_e(left, right).reshape(-1)
    rgb_error = left.astype(np.float64) - right.astype(np.float64)
    return {
        "deltaE2000Mean": float(np.mean(differences)),
        "deltaE2000Median": float(np.median(differences)),
        "deltaE2000P95": float(np.percentile(differences, 95)),
        "deltaE2000Max": float(np.max(differences)),
        "rgbRmse": float(np.sqrt(np.mean(np.square(rgb_error)))),
    }


def boundary_fraction(values: np.ndarray) -> dict:
    return {
        "atZero": float(np.mean(values <= 1e-7)),
        "atOne": float(np.mean(values >= 1.0 - 1e-7)),
    }


def look_key(path: Path) -> str:
    return re.sub(r"_CLog[23]_to_709_65\.cube$", "", path.name)


def summarize(rows: list[dict], field: str) -> dict:
    values = np.asarray([row[field]["deltaE2000Mean"] for row in rows])
    return {
        "lookMacroMeanDeltaE2000": float(np.mean(values)),
        "lookMacroMedianDeltaE2000": float(np.median(values)),
        "lookMacroP95DeltaE2000": float(np.percentile(values, 95)),
    }


def summarize_boundaries(rows: list[dict], field: str) -> dict:
    zero = np.asarray([row[field]["atZero"] for row in rows])
    one = np.asarray([row[field]["atOne"] for row in rows])
    return {
        "lookMacroMeanAtZero": float(np.mean(zero)),
        "lookMacroMaxAtZero": float(np.max(zero)),
        "lookMacroMeanAtOne": float(np.mean(one)),
        "lookMacroMaxAtOne": float(np.max(one)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    sources = generator.collect_lut_sources()
    canon = {
        (kind, look_key(path)): path
        for kind, path in sources
        if kind.startswith("canon_")
    }
    clog2_keys = {look for version, look in canon if version == "canon_clog2"}
    clog3_keys = {look for version, look in canon if version == "canon_clog3"}
    paired_keys = sorted(clog2_keys & clog3_keys)

    headers_valid = 0
    for (version, _), path in canon.items():
        header = "\n".join(path.read_text().splitlines()[:5])
        expected_log = "Canon Log 2" if version == "canon_clog2" else "Canon Log 3"
        if (
            f"Input Color Space : {expected_log} / Cinema Gamut" in header
            and "Output Color Space : BT.709" in header
        ):
            headers_valid += 1

    duplicate_pairs = []
    clog2_packages = sorted(
        path for path in generator.CANON_LUT_DIR.iterdir()
        if path.is_dir() and "log2" in path.name
    )
    if len(clog2_packages) >= 2:
        first = {path.name: path for path in (clog2_packages[0] / "65grid").glob("*.cube")}
        second = {path.name: path for path in (clog2_packages[1] / "65grid").glob("*.cube")}
        for name in sorted(first.keys() & second.keys()):
            duplicate_pairs.append({
                "name": name,
                "byteExact": sha256(first[name]) == sha256(second[name]),
            })

    probes = np.asarray(
        ((0, 0, 0), (1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1)),
        dtype=np.float32,
    )
    encoded_ranges = {}
    for version in ("canon_clog2", "canon_clog3"):
        legacy = legacy_srgb_to_canon_log(probes, version)
        corrected = generator.srgb_to_canon_log(probes, version)
        encoded_ranges[version] = {
            "legacyMin": float(legacy.min()),
            "legacyMax": float(legacy.max()),
            "correctedMin": float(corrected.min()),
            "correctedMax": float(corrected.max()),
            "probeRgbMaxAbsDifference": float(np.max(np.abs(legacy - corrected))),
        }

    rows = []
    for look in paired_keys:
        path2 = canon[("canon_clog2", look)]
        path3 = canon[("canon_clog3", look)]
        lut2 = generator.load_cube_lut(str(path2))
        lut3 = generator.load_cube_lut(str(path3))
        legacy2 = compose(lut2, "canon_clog2", legacy=True)
        legacy3 = compose(lut3, "canon_clog3", legacy=True)
        corrected2 = compose(lut2, "canon_clog2", legacy=False)
        corrected3 = compose(lut3, "canon_clog3", legacy=False)
        rows.append({
            "look": look,
            "legacyCLog2VsCLog3": comparison(legacy2, legacy3),
            "correctedCLog2VsCLog3": comparison(corrected2, corrected3),
            "legacyVsCorrectedCLog2": comparison(legacy2, corrected2),
            "legacyVsCorrectedCLog3": comparison(legacy3, corrected3),
            "legacyBoundaryFractionCLog2": boundary_fraction(legacy2),
            "legacyBoundaryFractionCLog3": boundary_fraction(legacy3),
            "correctedBoundaryFractionCLog2": boundary_fraction(corrected2),
            "correctedBoundaryFractionCLog3": boundary_fraction(corrected3),
        })

    legacy_pair = np.asarray([
        row["legacyCLog2VsCLog3"]["deltaE2000Mean"] for row in rows
    ])
    corrected_pair = np.asarray([
        row["correctedCLog2VsCLog3"]["deltaE2000Mean"] for row in rows
    ])
    improvement = legacy_pair - corrected_pair
    result = {
        "schemaVersion": 1,
        "sourceContract": {
            "canonLuts": len(canon),
            "validDeclaredHeaders": headers_valid,
            "pairedLooks": len(paired_keys),
            "unpairedCLog2": sorted(clog2_keys - clog3_keys),
            "unpairedCLog3": sorted(clog3_keys - clog2_keys),
            "duplicateCLog2PackageFiles": len(duplicate_pairs),
            "duplicateCLog2ByteExactFiles": sum(row["byteExact"] for row in duplicate_pairs),
        },
        "referenceContract": {
            "source": "ACES Input and Color Space Conversion Transforms, Canon ACES_to_CLog2/3_CGamut",
            "srgbToCinemaGamutMatrix": SRGB_TO_CINEMA_GAMUT.tolist(),
            "encodedProbeRanges": encoded_ranges,
        },
        "pairedLookConsistency": {
            "legacy": summarize(rows, "legacyCLog2VsCLog3"),
            "corrected": summarize(rows, "correctedCLog2VsCLog3"),
            "correctedBetterLooks": int(np.sum(improvement > 0)),
            "correctedWorseLooks": int(np.sum(improvement < 0)),
            "meanDeltaE2000Reduction": float(np.mean(improvement)),
            "medianDeltaE2000Reduction": float(np.median(improvement)),
        },
        "legacyTargetDrift": {
            "clog2": summarize(rows, "legacyVsCorrectedCLog2"),
            "clog3": summarize(rows, "legacyVsCorrectedCLog3"),
        },
        "outputBoundaryFractions": {
            "legacyCLog2": summarize_boundaries(rows, "legacyBoundaryFractionCLog2"),
            "legacyCLog3": summarize_boundaries(rows, "legacyBoundaryFractionCLog3"),
            "correctedCLog2": summarize_boundaries(rows, "correctedBoundaryFractionCLog2"),
            "correctedCLog3": summarize_boundaries(rows, "correctedBoundaryFractionCLog3"),
        },
        "worstLegacyTargetDrift": sorted(
            rows,
            key=lambda row: max(
                row["legacyVsCorrectedCLog2"]["deltaE2000Mean"],
                row["legacyVsCorrectedCLog3"]["deltaE2000Mean"],
            ),
            reverse=True,
        )[:10],
        "perLook": rows,
        "testSplitOpened": False,
        "decisionRule": (
            "Axis-v2 Canon targets are invalid if source headers require Cinema Gamut "
            "and the generator omitted that gamut transform or used non-reference transfer equations."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "sourceContract": result["sourceContract"],
        "pairedLookConsistency": result["pairedLookConsistency"],
        "legacyTargetDrift": result["legacyTargetDrift"],
        "topDrift": [
            {
                "look": row["look"],
                "clog2": row["legacyVsCorrectedCLog2"]["deltaE2000Mean"],
                "clog3": row["legacyVsCorrectedCLog3"]["deltaE2000Mean"],
            }
            for row in result["worstLegacyTargetDrift"][:5]
        ],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
