#!/usr/bin/env python3

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path


LOG = logging.getLogger(__name__)


def configure_logging():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")


def run_command(command):
    LOG.info("Running command: %s", " ".join(command))
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(command)}\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
    return result.stdout


def run(project_root, conda_exe, target_prefix, imports, output_path):
    configure_logging()
    python_snippet = """
import importlib
import json
import sys

mods = {}
errors = {}
for name in json.loads(sys.argv[1]):
    try:
        importlib.import_module(name)
        mods[name] = True
    except Exception as exc:
        mods[name] = False
        errors[name] = str(exc)

print(json.dumps({
    "python_version": sys.version.split()[0],
    "imports": mods,
    "errors": errors,
}, ensure_ascii=False))
"""
    target_prefix_path = Path(target_prefix)
    if not target_prefix_path.is_absolute():
        target_prefix_path = Path(project_root).resolve() / target_prefix_path
    raw = run_command(
        [
            conda_exe,
            "run",
            "-p",
            str(target_prefix_path.resolve()),
            "python",
            "-c",
            python_snippet,
            json.dumps(imports, ensure_ascii=False),
        ]
    )
    summary = json.loads(raw.strip())
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def build_parser():
    parser = argparse.ArgumentParser(description="Run a minimal health check against an installed conda environment.")
    parser.add_argument("--project-root", required=True, help="Pipeline project root")
    parser.add_argument("--conda-exe", required=True, help="Conda executable")
    parser.add_argument("--target-prefix", required=True, help="Installed environment prefix")
    parser.add_argument("--imports-json", default="[]", help="JSON array of packages to import")
    parser.add_argument("--output", required=True, help="Path to write the health-check summary JSON")
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    summary = run(
        project_root=args.project_root,
        conda_exe=args.conda_exe,
        target_prefix=args.target_prefix,
        imports=json.loads(args.imports_json),
        output_path=args.output,
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
