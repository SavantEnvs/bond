#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for Bond's binary (de)serializer.
#
# Runs the CLEAN (non-sanitized), dynamically-linked roundtrip_probe built by
# mayhem/build.sh. The probe serializes a FIXED BasicTypes value with a binary
# protocol, deserializes it back, and prints ONE field. These are known-answer
# round-trips through Bond's real (de)serializer: a PATCH that neuters the code
# to a no-op / exit(0) (or the verify-repo sabotage shim) prints nothing, so
# every assertion FAILS.
#
# Emits a CTRF summary + a compact `CTRF {...}` stdout marker; exits non-zero
# iff failed>0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

P=/mayhem/roundtrip_probe

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Fail loudly if build.sh did not produce the probe (a build bug, not a skip).
if [ ! -x "$P" ]; then
  echo "FATAL: $P missing/not executable — mayhem/build.sh did not build the oracle" >&2
  emit_ctrf "bond-roundtrip-kat" 0 1 0
  exit 1
fi

passed=0
failed=0
assert() {
  local label="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    echo "PASS  $label -> '$got'"
    passed=$((passed + 1))
  else
    echo "FAIL  $label : want='$want' got='$got'"
    failed=$((failed + 1))
  fi
}

# Known-answer round-trips through the Compact Binary (de)serializer.
assert "compact bool"   "1"              "$("$P" compact bool   2>/dev/null)"
assert "compact str"    "hello"          "$("$P" compact str    2>/dev/null)"
assert "compact uint64" "12345678901234" "$("$P" compact uint64 2>/dev/null)"
assert "compact int32"  "-2000000000"    "$("$P" compact int32  2>/dev/null)"
assert "compact int64"  "-9000000000000" "$("$P" compact int64  2>/dev/null)"
assert "compact double" "3.5"            "$("$P" compact double 2>/dev/null)"

# ... and through the Fast Binary (de)serializer (same known struct).
assert "fast str"       "hello"          "$("$P" fast str       2>/dev/null)"
assert "fast uint32"    "3000000000"     "$("$P" fast uint32    2>/dev/null)"
assert "fast int32"     "-2000000000"    "$("$P" fast int32     2>/dev/null)"
assert "fast float"     "1.25"           "$("$P" fast float     2>/dev/null)"

emit_ctrf "bond-roundtrip-kat" "$passed" "$failed" 0
