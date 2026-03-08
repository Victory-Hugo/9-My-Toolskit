#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CONFIG_PATH="$PROJECT_ROOT/conf/Config.json"

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "[ERROR] Config file not found: $CONFIG_PATH" >&2
    exit 1
fi

bash "$PROJECT_ROOT/script/check_env.sh"

BOOTSTRAP_PYTHON="python3"
CONFIG_LOADER="$PROJECT_ROOT/python/config_loader.py"

cfg() {
    "$BOOTSTRAP_PYTHON" "$CONFIG_LOADER" --config "$CONFIG_PATH" --key "$1"
}

STAGE="${1:-export}"
shift || true

BUNDLE_PATH_OVERRIDE=""
TARGET_PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-path)
            BUNDLE_PATH_OVERRIDE="$2"
            shift 2
            ;;
        --target-prefix)
            TARGET_PREFIX_OVERRIDE="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

PROJECT_NAME=$(cfg project.name)
OUTPUT_ROOT=$(cfg paths.output_root)
DIST_DIR=$(cfg paths.dist_dir)
TMP_DIR=$(cfg paths.tmp_dir)
LOG_DIR=$(cfg paths.log_dir)
CONDA_BIN=$(cfg tools.conda)
TAR_BIN=$(cfg tools.tar)
ENV_NAME=$(cfg export.env_name)
PIP_DOWNLOAD_MODE=$(cfg export.pip_download_mode)
IMPORTS_JSON=$(cfg export.healthcheck_imports)
TARGET_PREFIX=$(cfg install.target_prefix)
BUNDLE_INPUT=$(cfg install.bundle_input)

if [[ -n "$TARGET_PREFIX_OVERRIDE" ]]; then
    TARGET_PREFIX="$TARGET_PREFIX_OVERRIDE"
fi

case "$STAGE" in
    export)
        "$BOOTSTRAP_PYTHON" "$PROJECT_ROOT/python/export_bundle.py" \
            --project-root "$PROJECT_ROOT" \
            --project-name "$PROJECT_NAME" \
            --env-name "$ENV_NAME" \
            --output-root "$OUTPUT_ROOT" \
            --dist-dir "$DIST_DIR" \
            --tmp-dir "$TMP_DIR" \
            --log-dir "$LOG_DIR" \
            --conda-exe "$CONDA_BIN" \
            --tar-exe "$TAR_BIN" \
            --pip-download-mode "$PIP_DOWNLOAD_MODE" \
            --healthcheck-imports-json "$IMPORTS_JSON"
        ;;
    install)
        if [[ -n "$BUNDLE_PATH_OVERRIDE" ]]; then
            BUNDLE_INPUT="$BUNDLE_PATH_OVERRIDE"
        fi
        if [[ -z "$BUNDLE_INPUT" ]]; then
            echo "[ERROR] Bundle path is required for install stage. Use --bundle-path or set install.bundle_input." >&2
            exit 1
        fi
        "$BOOTSTRAP_PYTHON" "$PROJECT_ROOT/python/install_bundle.py" \
            --project-root "$PROJECT_ROOT" \
            --bundle-path "$BUNDLE_INPUT" \
            --target-prefix "$TARGET_PREFIX" \
            --log-dir "$LOG_DIR" \
            --tmp-dir "$TMP_DIR" \
            --conda-exe "$CONDA_BIN"
        ;;
    health)
        "$BOOTSTRAP_PYTHON" "$PROJECT_ROOT/python/health_check.py" \
            --project-root "$PROJECT_ROOT" \
            --conda-exe "$CONDA_BIN" \
            --target-prefix "$TARGET_PREFIX" \
            --imports-json "$IMPORTS_JSON" \
            --output "$PROJECT_ROOT/$LOG_DIR/health-check-installed.json"
        ;;
    *)
        echo "[ERROR] Unknown stage: $STAGE" >&2
        echo "Usage: bash pipe/pipeline.sh [export|install|health] [--bundle-path PATH] [--target-prefix PATH]" >&2
        exit 1
        ;;
esac
