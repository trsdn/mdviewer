#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import stat
import sys
import zipfile


def deterministic_zip_size(root: pathlib.Path) -> int:
    total = 0
    with open(os.devnull, "wb") as sink:
        with zipfile.ZipFile(
            sink, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
                relative = path.relative_to(root.parent).as_posix()
                metadata = path.lstat()
                info = zipfile.ZipInfo(relative + ("/" if path.is_dir() else ""))
                info.date_time = (1980, 1, 1, 0, 0, 0)
                info.create_system = 3
                info.external_attr = (stat.S_IMODE(metadata.st_mode) & 0xFFFF) << 16
                if path.is_symlink():
                    info.external_attr |= stat.S_IFLNK << 16
                    archive.writestr(info, os.readlink(path).encode())
                elif path.is_dir():
                    info.external_attr |= stat.S_IFDIR << 16
                    archive.writestr(info, b"")
                elif path.is_file():
                    info.external_attr |= stat.S_IFREG << 16
                    with path.open("rb") as source, archive.open(info, "w") as target:
                        while chunk := source.read(1024 * 1024):
                            target.write(chunk)
            total = archive.fp.tell()
    return total


def exceeds_limit(current: int, baseline: int) -> bool:
    increase = current - baseline
    return increase > 512 * 1024 and increase * 100 > baseline * 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("baseline_file", type=pathlib.Path)
    parser.add_argument("baseline_key")
    args = parser.parse_args()

    baseline_record = json.loads(args.baseline_file.read_text())[args.baseline_key]
    baseline = int(baseline_record["bytes"])
    current = (
        deterministic_zip_size(args.artifact)
        if args.artifact.is_dir()
        else args.artifact.stat().st_size
    )
    increase = current - baseline
    percent = increase * 100 / baseline
    print(
        f"Lite artifact size: {current} bytes; v2.0.1 baseline: {baseline} bytes; "
        f"change: {increase:+d} bytes ({percent:+.2f}%)."
    )
    if exceeds_limit(current, baseline):
        print(
            "Artifact size audit failed: increase exceeds both 524288 bytes and 2%.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
