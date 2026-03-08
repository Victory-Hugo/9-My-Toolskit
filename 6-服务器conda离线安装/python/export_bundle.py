#!/usr/bin/env python3

import argparse
import json
import logging
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
from time import sleep
from urllib.parse import urlparse
from urllib.request import urlopen


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


def run_command(command, *, env=None, capture_output=True):
    LOG.info("Running command: %s", " ".join(command))
    result = subprocess.run(
        command,
        check=False,
        env=env,
        text=True,
        capture_output=capture_output,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() if result.stderr else ""
        stdout = result.stdout.strip() if result.stdout else ""
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(command)}\nSTDOUT: {stdout}\nSTDERR: {stderr}"
        )
    return result


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def collect_env_metadata(conda_exe, env_name):
    conda_info = json.loads(run_command([conda_exe, "info", "--json"]).stdout)
    env_python = json.loads(
        run_command(
            [
                conda_exe,
                "run",
                "-n",
                env_name,
                "python",
                "-c",
                (
                    "import json,platform,sys; "
                    "print(json.dumps({"
                    "'python_version': sys.version.split()[0], "
                    "'implementation': platform.python_implementation(), "
                    "'platform': platform.platform(), "
                    "'machine': platform.machine(), "
                    "'system': platform.system()"
                    "}))"
                ),
            ]
        ).stdout
    )
    return {
        "exported_at_utc": datetime.now(timezone.utc).isoformat(),
        "env_name": env_name,
        "platform": platform.platform(),
        "system": platform.system(),
        "machine": platform.machine(),
        "architecture": platform.architecture()[0],
        "host_python_version": sys.version.split()[0],
        "conda_version": conda_info.get("conda_version"),
        "conda_root_prefix": conda_info.get("root_prefix"),
        "target_environment": env_python,
    }


def resolve_pip_requirements(pip_freeze_path):
    if not pip_freeze_path.exists():
        return False
    content = pip_freeze_path.read_text(encoding="utf-8").strip()
    return bool(content)


def normalize_requirement_line(line, version_map):
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None, None
    if " @ " in stripped:
        package_name = stripped.split(" @ ", 1)[0].strip()
        version = version_map.get(package_name.lower())
        if version is None:
            raise RuntimeError(f"Unable to resolve version for pip requirement: {stripped}")
        return f"{package_name}=={version}", stripped
    if stripped.startswith("-e "):
        editable_target = stripped[3:].strip()
        if "#egg=" in editable_target:
            package_name = editable_target.split("#egg=", 1)[1].strip()
            version = version_map.get(package_name.lower())
            if version is None:
                raise RuntimeError(f"Unable to resolve version for editable pip requirement: {stripped}")
            return f"{package_name}=={version}", stripped
    return stripped, None


def build_offline_pip_requirements(conda_exe, env_name, pip_freeze_path, offline_requirements_path):
    if not resolve_pip_requirements(pip_freeze_path):
        write_text(offline_requirements_path, "")
        return {"rewritten": []}

    pip_list = json.loads(
        run_command([conda_exe, "run", "-n", env_name, "python", "-m", "pip", "list", "--format=json"]).stdout
    )
    version_map = {item["name"].lower(): item["version"] for item in pip_list}
    normalized = []
    rewritten = []
    for raw_line in pip_freeze_path.read_text(encoding="utf-8").splitlines():
        normalized_line, original_line = normalize_requirement_line(raw_line, version_map)
        if normalized_line is None:
            continue
        normalized.append(normalized_line)
        if original_line is not None:
            rewritten.append({"original": original_line, "normalized": normalized_line})
    write_text(offline_requirements_path, "\n".join(normalized) + ("\n" if normalized else ""))
    return {"rewritten": rewritten}


def iter_explicit_urls(explicit_path):
    for raw_line in explicit_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line == "@EXPLICIT":
            continue
        yield line


def parse_archive_name(explicit_url):
    return Path(urlparse(explicit_url.split("#", 1)[0]).path).name


def copy_or_download_archive(explicit_url, conda_pkgs_dir, pkgs_dirs, retries=3):
    archive_name = parse_archive_name(explicit_url)
    destination = conda_pkgs_dir / archive_name
    if destination.exists():
        return destination

    for pkgs_dir in pkgs_dirs:
        candidate = pkgs_dir / archive_name
        if candidate.exists():
            shutil.copy2(candidate, destination)
            return destination

    download_url = explicit_url.split("#", 1)[0]
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            with urlopen(download_url, timeout=120) as response, destination.open("wb") as handle:
                shutil.copyfileobj(response, handle)
            return destination
        except Exception as exc:
            last_error = exc
            LOG.warning(
                "Failed to download %s (attempt %s/%s): %s",
                archive_name,
                attempt,
                retries,
                exc,
            )
            sleep(attempt)
    raise RuntimeError(f"Unable to stage conda archive {archive_name}: {last_error}")


def prepare_conda_cache(conda_exe, explicit_path, conda_pkgs_dir):
    conda_info = json.loads(run_command([conda_exe, "info", "--json"]).stdout)
    pkgs_dirs = [Path(path) for path in conda_info.get("pkgs_dirs", [])]
    staged = []
    for explicit_url in iter_explicit_urls(explicit_path):
        staged_path = copy_or_download_archive(explicit_url, conda_pkgs_dir, pkgs_dirs)
        staged.append(staged_path.name)
    return staged


def prepare_pip_cache(conda_exe, env_name, requirements_path, wheelhouse_dir, pip_download_mode):
    if not resolve_pip_requirements(requirements_path):
        LOG.info("No pip packages detected; skipping wheel download.")
        return {"downloaded": [], "source_distributions": []}

    command = [
        conda_exe,
        "run",
        "-n",
        env_name,
        "python",
        "-m",
        "pip",
        "download",
        "--dest",
        str(wheelhouse_dir),
        "-r",
        str(requirements_path),
    ]
    if pip_download_mode == "prefer_binary":
        try:
            run_command(command[:8] + ["--only-binary=:all:"] + command[8:])
        except RuntimeError:
            LOG.warning("Binary-only pip download failed; retrying with source distributions allowed.")
            run_command(command)
    else:
        run_command(command)

    downloaded = sorted(p.name for p in wheelhouse_dir.iterdir() if p.is_file())
    source_distributions = [
        name for name in downloaded if name.endswith((".tar.gz", ".zip", ".tar.bz2", ".tar.xz"))
    ]
    return {"downloaded": downloaded, "source_distributions": source_distributions}


def iter_files(root):
    for path in sorted(root.rglob("*")):
        if path.is_file():
            yield path


def calculate_sha256(path):
    hasher = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def build_manifest(bundle_dir, metadata, pip_cache_summary, project_name):
    files = []
    for file_path in iter_files(bundle_dir):
        relpath = file_path.relative_to(bundle_dir).as_posix()
        if relpath in {"metadata/manifest.json", "metadata/sha256.txt"}:
            continue
        files.append(
            {
                "path": relpath,
                "size_bytes": file_path.stat().st_size,
                "sha256": calculate_sha256(file_path),
            }
        )
    conda_archives = [item["path"] for item in files if item["path"].startswith("conda_pkgs/")]
    manifest = {
        "project_name": project_name,
        "generated_at_utc": metadata["exported_at_utc"],
        "env_name": metadata["env_name"],
        "conda_archive_count": len(conda_archives),
        "pip_artifact_count": len(pip_cache_summary["downloaded"]),
        "pip_source_distributions": pip_cache_summary["source_distributions"],
        "files": files,
    }
    return manifest


def write_checksums(bundle_dir, checksum_path):
    lines = []
    for file_path in iter_files(bundle_dir):
        relpath = file_path.relative_to(bundle_dir).as_posix()
        if relpath == "metadata/sha256.txt":
            continue
        lines.append(f"{calculate_sha256(file_path)}  {relpath}")
    write_text(checksum_path, "\n".join(lines) + "\n")


def write_install_guide(path, project_name, env_name):
    content = f"""# Offline Install Guide

Project: {project_name}
Environment: {env_name}

1. Transfer the generated `tar.gz` package or the unpacked `bundle/` directory to the offline machine.
2. Place this project on the offline machine and set `install.bundle_input` in `conf/Config.json`, or pass `--bundle-path`.
3. Run:

```bash
bash pipe/pipeline.sh install --bundle-path path/to/bundle-or-tar.gz
```

4. Verify the installed environment:

```bash
bash pipe/pipeline.sh health
```
"""
    write_text(path, content)


def create_archive(tar_exe, source_dir, archive_path):
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            tar_exe,
            "-czf",
            str(archive_path),
            "-C",
            str(source_dir.parent),
            source_dir.name,
        ]
    )


def run(
    project_root,
    project_name,
    env_name,
    output_root,
    dist_dir,
    tmp_dir,
    log_dir,
    conda_exe,
    tar_exe,
    pip_download_mode,
    healthcheck_imports,
):
    run_id = datetime.now().strftime("%Y%m%dT%H%M%S")
    project_root = Path(project_root).resolve()
    export_root = project_root / output_root / "exports" / run_id
    bundle_dir = export_root / "bundle"
    metadata_dir = bundle_dir / "metadata"
    conda_pkgs_dir = bundle_dir / "conda_pkgs"
    wheelhouse_dir = bundle_dir / "wheelhouse"
    logs_dir = export_root / "logs"
    archive_path = project_root / dist_dir / f"{project_name}-{env_name}-{run_id}.tar.gz"

    log_path = project_root / log_dir / f"export-{run_id}.log"
    configure_logging(log_path)

    metadata_dir.mkdir(parents=True, exist_ok=True)
    conda_pkgs_dir.mkdir(parents=True, exist_ok=True)
    wheelhouse_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    environment_yml = metadata_dir / "environment.yml"
    explicit_txt = metadata_dir / "explicit.txt"
    pip_freeze_txt = metadata_dir / "pip_freeze.txt"
    pip_requirements_offline_txt = metadata_dir / "pip_requirements_offline.txt"
    env_metadata_json = metadata_dir / "env_metadata.json"
    manifest_json = metadata_dir / "manifest.json"
    checksum_txt = metadata_dir / "sha256.txt"
    install_guide = metadata_dir / "INSTALL.md"

    write_text(environment_yml, run_command([conda_exe, "env", "export", "-n", env_name, "--no-builds"]).stdout)
    write_text(explicit_txt, run_command([conda_exe, "list", "-n", env_name, "--explicit"]).stdout)
    write_text(
        pip_freeze_txt,
        run_command([conda_exe, "run", "-n", env_name, "python", "-m", "pip", "freeze"]).stdout,
    )

    metadata = collect_env_metadata(conda_exe, env_name)
    metadata["project_name"] = project_name
    metadata["healthcheck_imports"] = healthcheck_imports
    staged_conda_archives = prepare_conda_cache(conda_exe, explicit_txt, conda_pkgs_dir)
    metadata["conda_archives_staged"] = staged_conda_archives
    pip_rewrite_summary = build_offline_pip_requirements(
        conda_exe=conda_exe,
        env_name=env_name,
        pip_freeze_path=pip_freeze_txt,
        offline_requirements_path=pip_requirements_offline_txt,
    )
    metadata["pip_requirements_rewritten"] = pip_rewrite_summary["rewritten"]
    write_text(env_metadata_json, json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
    pip_cache_summary = prepare_pip_cache(
        conda_exe=conda_exe,
        env_name=env_name,
        requirements_path=pip_requirements_offline_txt,
        wheelhouse_dir=wheelhouse_dir,
        pip_download_mode=pip_download_mode,
    )

    write_install_guide(install_guide, project_name, env_name)

    manifest = build_manifest(
        bundle_dir=bundle_dir,
        metadata=metadata,
        pip_cache_summary=pip_cache_summary,
        project_name=project_name,
    )
    write_text(manifest_json, json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    write_checksums(bundle_dir, checksum_txt)

    create_archive(tar_exe, bundle_dir, archive_path)

    summary = {
        "run_id": run_id,
        "bundle_dir": str(bundle_dir),
        "archive_path": str(archive_path),
        "log_path": str(log_path),
        "healthcheck_imports": healthcheck_imports,
    }
    LOG.info("Export completed: %s", json.dumps(summary, ensure_ascii=False))
    return summary


def build_parser():
    parser = argparse.ArgumentParser(description="Export a conda environment into an offline delivery bundle.")
    parser.add_argument("--project-root", required=True, help="Pipeline project root")
    parser.add_argument("--project-name", required=True, help="Project name for metadata and archive naming")
    parser.add_argument("--env-name", required=True, help="Conda environment name to export")
    parser.add_argument("--output-root", required=True, help="Relative output directory")
    parser.add_argument("--dist-dir", required=True, help="Relative archive output directory")
    parser.add_argument("--tmp-dir", required=True, help="Relative temp directory")
    parser.add_argument("--log-dir", required=True, help="Relative log directory")
    parser.add_argument("--conda-exe", required=True, help="Conda executable")
    parser.add_argument("--tar-exe", required=True, help="Tar executable")
    parser.add_argument(
        "--pip-download-mode",
        default="prefer_binary",
        choices=["prefer_binary", "allow_source"],
        help="Download wheels first or allow source distributions immediately",
    )
    parser.add_argument(
        "--healthcheck-imports-json",
        default="[]",
        help="JSON array of packages to import during post-install health checks",
    )
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    summary = run(
        project_root=args.project_root,
        project_name=args.project_name,
        env_name=args.env_name,
        output_root=args.output_root,
        dist_dir=args.dist_dir,
        tmp_dir=args.tmp_dir,
        log_dir=args.log_dir,
        conda_exe=args.conda_exe,
        tar_exe=args.tar_exe,
        pip_download_mode=args.pip_download_mode,
        healthcheck_imports=json.loads(args.healthcheck_imports_json),
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
