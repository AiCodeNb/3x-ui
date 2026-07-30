#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import urllib.request
from pathlib import Path

from apply_zh_cn import SCRIPT_FILES, apply


UPSTREAM_RAW = "https://raw.githubusercontent.com/MHSanaei/3x-ui/main"
UPSTREAM_COMMIT = "https://api.github.com/repos/MHSanaei/3x-ui/commits/main"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "3x-ui-zh-cn-sync"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="3x-ui-upstream-") as directory:
        source_dir = Path(directory)
        for filename in SCRIPT_FILES:
            (source_dir / filename).write_bytes(fetch(f"{UPSTREAM_RAW}/{filename}"))
        report = apply(source_dir, repo)

    commit = json.loads(fetch(UPSTREAM_COMMIT).decode("utf-8"))
    metadata = {
        "repository": "MHSanaei/3x-ui",
        "branch": "main",
        "commit": commit["sha"],
        "translation_replacements": report,
    }
    (repo / "localization" / "upstream.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
