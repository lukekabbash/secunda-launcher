#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/secunda-readiness.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Compile the real services with deterministic filesystem/process doubles.
# Concatenation lets FoundationNetworking be imported for Linux-only test runs.
cat "$ROOT/tests/launch-readiness/ServiceDoubles.swift" \
    "$ROOT/app/Service/LaunchReadinessPolicy.swift" \
    "$ROOT/app/Service/RuntimeManager.swift" \
    "$ROOT/app/Service/VoiceAudioService.swift" \
    "$ROOT/tests/launch-readiness/RegressionMain.swift" > "$WORK/Regression.swift"
swiftc -swift-version 5 -parse-as-library "$WORK/Regression.swift" -o "$WORK/regression"
"$WORK/regression"
