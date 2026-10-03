#!/usr/bin/env python3
"""Run mkdocs-speech on the fixture and require exactly the expected companion.

usage: check.py MKDOCS_SPEECH [--control]

--control mutates the expectation (one word) and requires the comparison to fail,
which shows the check can fail.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def companion(tool):
    with tempfile.TemporaryDirectory() as work:
        shutil.copy(HERE / "fixture.md", work)
        subprocess.run([tool, work], check=True, capture_output=True)
        data = json.loads((Path(work) / "fixture.speech.json").read_text(encoding="utf-8"))
    data.pop("_source")
    return data


def main(argv):
    expected = json.loads((HERE / "expected.json").read_text(encoding="utf-8"))
    if "--control" in argv:
        key = next(iter(expected))
        expected[key][0]["text"] += " altered"
    actual = companion(argv[0])
    same = actual == expected
    if "--control" in argv:
        print("control:", "FAIL as required" if not same else "did not fail, the check is blind")
        return 0 if not same else 1
    if not same:
        print(json.dumps(actual, indent=2, ensure_ascii=False))
        print("companion differs from expected.json")
        return 1
    print("companion equals expected.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
