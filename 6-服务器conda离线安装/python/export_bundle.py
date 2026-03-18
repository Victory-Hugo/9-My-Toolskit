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
from urllib.parse import unquote, urlparse
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


def resolve_env_python(conda_exe, env_name):
    conda_prefix = Path(conda_exe).resolve().parent.parent
    env_python = conda_prefix / "envs" / env_name / "bin" / "python"
    if env_python.exists():
        return str(env_python)
    return None


def run_pip_freeze(conda_exe, env_name):
    """
    Prefer the env's activated python when available.
    `conda run` can fail in environments with broken compiler wrapper links.
    """
    env_python = resolve_env_python(conda_exe, env_name)
    candidates = []
    if env_python:
        candidates.append([env_python, "-m", "pip", "freeze"])
    candidates.append([conda_exe, "run", "-n", env_name, "python", "-m", "pip", "freeze"])

    last_error = None
    for command in candidates:
        try:
            return run_command(command).stdout, None, " ".join(command)
        except RuntimeError as exc:
            last_error = str(exc)
            LOG.warning("pip freeze command failed: %s", exc)
    return "", last_error, None


def collect_env_metadata(conda_exe, env_name):
    conda_info = json.loads(run_command([conda_exe, "info", "--json"]).stdout)
    env_python_exe = resolve_env_python(conda_exe, env_name)
    if env_python_exe is None:
        raise RuntimeError(f"Unable to locate environment python for {env_name}")
    env_python = json.loads(
        run_command(
            [
                env_python_exe,
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


def canonicalize_local_requirement_target(target):
    parsed = urlparse(target)
    if parsed.scheme == "file":
        path = unquote(parsed.path)
        if parsed.netloc and parsed.netloc != "localhost":
            path = f"//{parsed.netloc}{path}"
        return str(Path(path).expanduser().resolve())
    return str(Path(target).expanduser().resolve())


def is_vcs_requirement_target(target):
    return target.startswith(("git+", "hg+", "svn+", "bzr+"))


def collect_pip_managed_packages(conda_exe, env_name):
    conda_packages = json.loads(run_command([conda_exe, "list", "-n", env_name, "--json"]).stdout)
    return {
        item["name"].lower()
        for item in conda_packages
        if item.get("channel") == "pypi" and item.get("name")
    }


def normalize_requirement_line(line, version_map, editable_location_map):
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None, None, None, None
    if " @ " in stripped:
        package_name, requirement_target = [part.strip() for part in stripped.split(" @ ", 1)]
        version = version_map.get(package_name.lower())
        if version is None:
            raise RuntimeError(f"Unable to resolve version for pip requirement: {stripped}")
        source_requirement = stripped if is_vcs_requirement_target(requirement_target) else None
        return f"{package_name}=={version}", stripped, package_name, source_requirement
    if stripped.startswith("-e "):
        editable_target = stripped[3:].strip()
        if "#egg=" in editable_target:
            package_name = editable_target.split("#egg=", 1)[1].strip()
            version = version_map.get(package_name.lower())
            if version is None:
                raise RuntimeError(f"Unable to resolve version for editable pip requirement: {stripped}")
            source_requirement = editable_target if is_vcs_requirement_target(editable_target) else None
            return f"{package_name}=={version}", stripped, package_name, source_requirement
        package_name = editable_location_map.get(canonicalize_local_requirement_target(editable_target))
        if package_name is None:
            raise RuntimeError(f"Unable to resolve package name for editable pip requirement: {stripped}")
        version = version_map.get(package_name.lower())
        if version is None:
            raise RuntimeError(f"Unable to resolve version for editable pip requirement: {stripped}")
        return f"{package_name}=={version}", stripped, package_name, None
    package_name = stripped.split(";", 1)[0].strip()
    for delimiter in ("==", "===", ">=", "<=", "~=", "!=", ">", "<"):
        if delimiter in package_name:
            package_name = package_name.split(delimiter, 1)[0].strip()
            break
    return stripped, None, package_name, None


def build_offline_pip_requirements(
    conda_exe,
    env_name,
    pip_freeze_path,
    offline_requirements_path,
    download_requirements_path,
):
    if not resolve_pip_requirements(pip_freeze_path):
        write_text(offline_requirements_path, "")
        write_text(download_requirements_path, "")
        return {"rewritten": [], "vcs_requirements": []}

    pip_managed_packages = collect_pip_managed_packages(conda_exe, env_name)
    if not pip_managed_packages:
        write_text(offline_requirements_path, "")
        write_text(download_requirements_path, "")
        return {"rewritten": [], "vcs_requirements": []}

    pip_list = json.loads(
        run_command([conda_exe, "run", "-n", env_name, "python", "-m", "pip", "list", "--format=json"]).stdout
    )
    editable_pip_list = json.loads(
        run_command([conda_exe, "run", "-n", env_name, "python", "-m", "pip", "list", "--editable", "--format=json"]).stdout
    )
    version_map = {item["name"].lower(): item["version"] for item in pip_list}
    editable_location_map = {
        canonicalize_local_requirement_target(item["editable_project_location"]): item["name"]
        for item in editable_pip_list
        if item.get("editable_project_location") and item.get("name")
    }
    normalized = []
    download_requirements = []
    rewritten = []
    vcs_requirements = []
    for raw_line in pip_freeze_path.read_text(encoding="utf-8").splitlines():
        normalized_line, original_line, package_name, source_requirement = normalize_requirement_line(
            raw_line,
            version_map,
            editable_location_map,
        )
        if normalized_line is None:
            continue
        if package_name is None or package_name.lower() not in pip_managed_packages:
            continue
        normalized.append(normalized_line)
        if source_requirement is None:
            download_requirements.append(normalized_line)
        else:
            vcs_requirements.append(
                {
                    "package": package_name,
                    "normalized": normalized_line,
                    "source": source_requirement,
                }
            )
        if original_line is not None:
            rewritten.append({"original": original_line, "normalized": normalized_line})
    write_text(offline_requirements_path, "\n".join(normalized) + ("\n" if normalized else ""))
    write_text(download_requirements_path, "\n".join(download_requirements) + ("\n" if download_requirements else ""))
    return {"rewritten": rewritten, "vcs_requirements": vcs_requirements}


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


def prepare_pip_cache(
    conda_exe,
    env_name,
    requirements_path,
    download_requirements_path,
    wheelhouse_dir,
    pip_download_mode,
    vcs_requirements,
):
    if not resolve_pip_requirements(requirements_path):
        LOG.info("No pip packages detected; skipping wheel download.")
        return {"downloaded": [], "source_distributions": []}

    if resolve_pip_requirements(download_requirements_path):
        for requirement in download_requirements_path.read_text(encoding="utf-8").splitlines():
            requirement = requirement.strip()
            if not requirement:
                continue
            command = [
                conda_exe,
                "run",
                "-n",
                env_name,
                "python",
                "-m",
                "pip",
                "download",
                "--no-deps",
                "--dest",
                str(wheelhouse_dir),
                requirement,
            ]
            if pip_download_mode == "prefer_binary":
                try:
                    run_command(command[:9] + ["--only-binary=:all:"] + command[9:])
                except RuntimeError:
                    LOG.warning(
                        "Binary-only pip download failed for %s; retrying with source distributions allowed.",
                        requirement,
                    )
                    run_command(command)
            else:
                run_command(command)

    for requirement in vcs_requirements:
        run_command(
            [
                conda_exe,
                "run",
                "-n",
                env_name,
                "python",
                "-m",
                "pip",
                "wheel",
                "--no-deps",
                "--wheel-dir",
                str(wheelhouse_dir),
                requirement["source"],
            ]
        )

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
    pip_requirements_download_txt = metadata_dir / "pip_requirements_download.txt"
    env_metadata_json = metadata_dir / "env_metadata.json"
    manifest_json = metadata_dir / "manifest.json"
    checksum_txt = metadata_dir / "sha256.txt"
    install_guide = metadata_dir / "INSTALL.md"

    write_text(environment_yml, run_command([conda_exe, "env", "export", "-n", env_name, "--no-builds"]).stdout)
    write_text(explicit_txt, run_command([conda_exe, "list", "-n", env_name, "--explicit"]).stdout)
    pip_freeze_stdout, pip_freeze_error, pip_freeze_command = run_pip_freeze(conda_exe, env_name)
    write_text(pip_freeze_txt, pip_freeze_stdout)

    metadata = collect_env_metadata(conda_exe, env_name)
    metadata["project_name"] = project_name
    metadata["healthcheck_imports"] = healthcheck_imports
    metadata["pip_freeze_command"] = pip_freeze_command
    metadata["pip_freeze_error"] = pip_freeze_error
    staged_conda_archives = prepare_conda_cache(conda_exe, explicit_txt, conda_pkgs_dir)
    metadata["conda_archives_staged"] = staged_conda_archives
    pip_rewrite_summary = build_offline_pip_requirements(
        conda_exe=conda_exe,
        env_name=env_name,
        pip_freeze_path=pip_freeze_txt,
        offline_requirements_path=pip_requirements_offline_txt,
        download_requirements_path=pip_requirements_download_txt,
    )
    metadata["pip_requirements_rewritten"] = pip_rewrite_summary["rewritten"]
    metadata["pip_vcs_requirements"] = pip_rewrite_summary["vcs_requirements"]
    write_text(env_metadata_json, json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
    pip_cache_summary = prepare_pip_cache(
        conda_exe=conda_exe,
        env_name=env_name,
        requirements_path=pip_requirements_offline_txt,
        download_requirements_path=pip_requirements_download_txt,
        wheelhouse_dir=wheelhouse_dir,
        pip_download_mode=pip_download_mode,
        vcs_requirements=pip_rewrite_summary["vcs_requirements"],
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
