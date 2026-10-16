#!/usr/bin/env python3
"""Validate an agent report against scripts/report.schema.json (standard library only).

The agent writes agent-out/report.json at the end of a run. CI validates it
here before rendering it into the pull request comment, so a malformed or
truncated report is caught deterministically instead of trusted.

Supported schema features: type (object/array/string/integer/boolean),
required, properties, additionalProperties: false, enum, minimum, items.
That is all report.schema.json uses; anything else is ignored.

Usage: validate-report.py <report.json> [schema.json]
Exit 0 when valid, 1 when invalid (reasons on stderr), 2 on usage errors.
"""
import json
import os
import sys

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "integer": int,
    "boolean": bool,
}


def validate(value, schema, path, errors):
    expected = schema.get("type")
    if expected:
        py_type = TYPES.get(expected)
        if py_type is int and isinstance(value, bool):
            errors.append(f"{path}: expected integer, got boolean")
            return
        if py_type and not isinstance(value, py_type):
            errors.append(f"{path}: expected {expected}, got {type(value).__name__}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} is not one of {schema['enum']}")
    if "minimum" in schema and isinstance(value, int) and value < schema["minimum"]:
        errors.append(f"{path}: {value} is below the minimum {schema['minimum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing required key '{key}'")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in props:
                    errors.append(f"{path}: unexpected key '{key}'")
        for key, sub in props.items():
            if key in value:
                validate(value[key], sub, f"{path}.{key}", errors)
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            validate(item, schema["items"], f"{path}[{i}]", errors)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    report_path = argv[1]
    schema_path = argv[2] if len(argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "report.schema.json"
    )
    try:
        with open(schema_path, encoding="utf-8") as fh:
            schema = json.load(fh)
        with open(report_path, encoding="utf-8") as fh:
            report = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"validate-report: cannot read input: {exc}", file=sys.stderr)
        return 1
    errors = []
    validate(report, schema, "report", errors)
    if errors:
        for err in errors:
            print(f"validate-report: {err}", file=sys.stderr)
        return 1
    print(f"validate-report: {report_path} is valid")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
