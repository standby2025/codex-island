#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT
swiftc -parse-as-library -o "$OUT_DIR/metrics-tests" Sources/Metrics/UsageMetrics.swift Tests/UsageMetricsTests.swift
"$OUT_DIR/metrics-tests"
