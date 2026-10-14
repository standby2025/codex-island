#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT
swiftc -parse-as-library -o "$OUT_DIR/metrics-tests" Sources/Metrics/UsageMetrics.swift Tests/UsageMetricsTests.swift
"$OUT_DIR/metrics-tests"
swiftc -parse-as-library -o "$OUT_DIR/metrics-exporter-tests" \
  Sources/Model/IslandProvider.swift Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift Sources/Usage/ConnectedUsage.swift \
  Sources/Metrics/UsageMetrics.swift Sources/Metrics/MetricsExporter.swift \
  Tests/MetricsExporterTests.swift
"$OUT_DIR/metrics-exporter-tests"
