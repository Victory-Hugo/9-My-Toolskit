#!/usr/bin/env python3

import argparse
import json
import logging
import shutil
import subprocess
import sys
import tarfile
from datetime import datetime
from hashlib import sha256
from pathlib import Path
from urllib.parse import urlparse


LOG = logging.getLogger(__name__)


def configure_logging(log_path):
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_path, encoding="utf-8"),
            logging.StreamHandler(sys.stderr),
        ],
    )


def run_command(command):
    LOG.info("Running command: %s", " ".join(command))
    result = subprocess.run(command, check=False, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(command)}\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
    return result


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def hash_file(path):
    hasher = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def resolve_bundle(bundle_path, extraction_root):
    bundle_path = Path(bundle_path).resolve()
    if bundle_path.is_dir():
        return bundle_path
    if not bundle_path.is_file():
        raise FileNotFoundError(f"Bundle path not found: {bundle_path}")
    extraction_root.mkdir(parents=True, exist_ok=True)
    with tarfile.open(bundle_path, "r:gz") as archive:
        archive.extractall(extraction_root)
    candidates = [path for path in extraction_root.iterdir() if path.is_dir()]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one top-level bundle directory after extraction, found {len(candidates)}")
    return candidates[0]


def verify_checksums(bundle_dir):
    checksum_path = bundle_dir / "metadata" / "sha256.txt"
    if not checksum_path.exists():
        raise FileNotFoundError(f"Checksum file missing: {checksum_path}")
    for raw_line in checksum_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        digest, relpath = line.split("  ", 1)
        file_path = bundle_dir / relpath
        if not file_path.exists():
            raise FileNotFoundError(f"Manifest file missing from bundle: {relpath}")
        current_digest = hash_file(file_path)
        if current_digest != digest:
            raise RuntimeError(f"Checksum mismatch for {relpath}: expected {digest}, got {current_digest}")


def build_explicit_local(bundle_dir):
    explicit_path = bundle_dir / "metadata" / "explicit.txt"
    conda_pkgs_dir = bundle_dir / "conda_pkgs"
    output_path = bundle_dir / "metadata" / "explicit_local.txt"
    archives = {path.name: path.resolve() for path in conda_pkgs_dir.iterdir() if path.is_file()}
    lines = ["@EXPLICIT"]
    for raw_line in explicit_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line == "@EXPLICIT":
            continue
        parsed = urlparse(line)
        archive_name = Path(parsed.path).name
        if archive_name not in archives:
            raise FileNotFoundError(f"Missing conda archive required by explicit spec: {archive_name}")
        lines.append(archives[archive_name].as_uri())
    write_text(output_path, "\n".join(lines) + "\n")
    return output_path


def install_conda_environment(conda_exe, target_prefix, explicit_local_path):
    target_prefix = Path(target_prefix)
    if target_prefix.exists():
        raise FileExistsError(f"Target prefix already exists: {target_prefix}")
    run_command(
        [
            conda_exe,
            "create",
            "--yes",
            "--offline",
            "--prefix",
            str(target_prefix),
            "--file",
            str(explicit_local_path),
        ]
    )


def install_pip_packages(conda_exe, target_prefix, bundle_dir):
    pip_freeze = bundle_dir / "metadata" / "pip_requirements_offline.txt"
    if not pip_freeze.exists():
        pip_freeze = bundle_dir / "metadata" / "pip_freeze.txt"
    wheelhouse = bundle_dir / "wheelhouse"
    if not pip_freeze.exists():
        return
    requirements = pip_freeze.read_text(encoding="utf-8").strip()
    if not requirements:
        LOG.info("No pip packages to install.")
        return
    run_command(
        [
            conda_exe,
            "run",
            "-p",
            str(Path(target_prefix).resolve()),
            "python",
            "-m",
            "pip",
            "install",
            "--no-index",
            "--find-links",
            str(wheelhouse.resolve()),
            "-r",
            str(pip_freeze.resolve()),
        ]
    )


def run(project_root, bundle_path, target_prefix, log_dir, tmp_dir, conda_exe):
    timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    project_root = Path(project_root).resolve()
    log_path = project_root / log_dir / f"install-{timestamp}.log"
    configure_logging(log_path)

    extraction_root = project_root / tmp_dir / f"install_extract_{timestamp}"
    bundle_path = Path(bundle_path)
    if not bundle_path.is_absolute():
        bundle_path = project_root / bundle_path
    target_prefix_path = Path(target_prefix)
    if not target_prefix_path.is_absolute():
        target_prefix_path = project_root / target_prefix_path

    bundle_dir = resolve_bundle(bundle_path, extraction_root)
    verify_checksums(bundle_dir)
    explicit_local = build_explicit_local(bundle_dir)
    install_conda_environment(conda_exe, target_prefix_path, explicit_local)
    install_pip_packages(conda_exe, target_prefix_path, bundle_dir)

    summary = {
        "bundle_dir": str(bundle_dir),
        "target_prefix": str(target_prefix_path.resolve()),
        "log_path": str(log_path),
    }
    LOG.info("Offline installation completed: %s", json.dumps(summary, ensure_ascii=False))
    return summary


def build_parser():
    parser = argparse.ArgumentParser(description="Install an offline conda delivery bundle.")
    parser.add_argument("--project-root", required=True, help="Pipeline project root")
    parser.add_argument("--bundle-path", required=True, help="Path to bundle directory or tar.gz package")
    parser.add_argument("--target-prefix", required=True, help="Target conda prefix to create")
    parser.add_argument("--log-dir", required=True, help="Relative log directory")
    parser.add_argument("--tmp-dir", required=True, help="Relative temp directory")
    parser.add_argument("--conda-exe", required=True, help="Conda executable")
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    summary = run(
        project_root=args.project_root,
        bundle_path=args.bundle_path,
        target_prefix=args.target_prefix,
        log_dir=args.log_dir,
        tmp_dir=args.tmp_dir,
        conda_exe=args.conda_exe,
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
