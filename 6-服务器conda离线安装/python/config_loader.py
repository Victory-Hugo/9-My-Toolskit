#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


def lookup_key(data, dotted_key):
    current = data
    for part in dotted_key.split("."):
        if not isinstance(current, dict) or part not in current:
            raise KeyError(f"Missing config key: {dotted_key}")
        current = current[part]
    return current


def run(config_path, dotted_key):
    with Path(config_path).open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    return lookup_key(data, dotted_key)


def build_parser():
    parser = argparse.ArgumentParser(description="Read a value from conf/Config.json.")
    parser.add_argument("--config", required=True, help="Path to Config.json")
    parser.add_argument("--key", required=True, help="Dotted key such as paths.output_root")
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    value = run(args.config, args.key)
    if isinstance(value, (dict, list)):
        print(json.dumps(value, ensure_ascii=False))
    else:
        print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
