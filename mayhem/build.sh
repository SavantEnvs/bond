#!/usr/bin/env bash
#
# mayhem/build.sh — build Bond's binary-deserializer fuzz harnesses + a behavioral oracle probe.
#
# Fuzz targets (in-process libFuzzer, byte-in, no file I/O):
#   fuzz_compact_binary — bond::Deserialize<tests::ComplexTypes> via CompactBinaryReader
#   fuzz_fast_binary    — bond::Deserialize<tests::ComplexTypes> via FastBinaryReader
# ComplexTypes (compiler/tests/generated/complex_types_*) is the richest self-contained
# schema Bond ships pre-generated: lists, sets, vector<blob>, nullable, map, bonded<>.
#
# Bond's C++ runtime is (almost) header-only but needs a handful of generated headers for
# its OWN core IDL (idl/bond/core/{bond,bond_const}.bond -> bond_types.h, bond_const_enum.h,
# ...). Those are produced by the Haskell `gbc` compiler and are NOT checked into upstream.
# We PRE-GENERATED them once with gbc and committed them under mayhem/generated/ — so this
# build needs no Haskell toolchain and runs fully offline (air-gap safe). Boost headers +
# boost_thread/system (bond uses boost::call_once on clang) are baked as a root apt layer.
#
# The PROJECT/runtime code is compiled with $SANITIZER_FLAGS AND -fsanitize=fuzzer-no-link
# UNCONDITIONALLY so the fuzzed deserializer carries SanCov instrumentation (else 0 edges in
# Mayhem), plus $DEBUG_FLAGS AFTER $SANITIZER_FLAGS so DWARF is <4 (the base's flags end in a
# plain -g = DWARF5). The oracle probe is a SEPARATE clean build (no sanitizer, no -gdwarf-3),
# dynamically linked so mayhem/test.sh's LD_PRELOAD sabotage shim can neuter it.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# Two UBSan checks fire on idioms INHERENT to parsing untrusted binary, so with the base's
# -fno-sanitize-recover=all they abort on nearly every input and STARVE coverage (netnew §6b) —
# relax ONLY these two; ASan and the rest of UBSan stay halting, and ASan remains the real detector
# for the memory-safety (OOB read/write) bugs this deserializer target exists to find:
#   * alignment — InputBuffer::Read does deliberate UNALIGNED x86 reads ("x86/x64 performance tweak:
#     we can access memory unaligned", cpp/inc/bond/stream/input_buffer.h:152), tripping on every
#     multi-byte read.
#   * enum      — the tagged readers load the wire type tag straight into a BondDataType enum
#     (fast_binary.h:397 / compact_binary.h), so ANY invalid/unknown tag byte (exactly what a fuzzer
#     produces) is an out-of-range enum load.
#   * bool      — InputBuffer::Read loads a raw wire byte into a C++ `bool`; any byte other than 0/1
#     (again, exactly what a fuzzer produces) is an invalid-bool load.
# All three are "load an untrusted wire byte into a typed field" UB — benign on the target ABI and
# inherent to a binary deserializer; empirically 100% of the crashes ASan/UBSan found in local fuzzing
# were these (ZERO memory-safety findings), so leaving them halting would drown the target in noise
# and starve exploration. (Appended AFTER $SANITIZER_FLAGS so -fno-sanitize= wins; harmless if empty.)
SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=alignment,enum,bool"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"

SRC="${SRC:-/mayhem}"
cd "$SRC"

GEN="$SRC/mayhem/generated"                # pre-generated core bond IDL headers (committed)
SCHEMA="$SRC/compiler/tests/generated"     # pre-generated test schemas (upstream)
# Bond's core headers transitively include rapidjson (protocol/detail/rapidjson_helper.h), which
# upstream ships as a GIT SUBMODULE (thirdparty/rapidjson) — absent from a plain `git clone` (the CI /
# verify-repo build context). We VENDOR the exact pinned submodule headers (commit 8f4c021f) under
# mayhem/vendor so the build is self-contained and air-gap safe, independent of submodule checkout.
RAPIDJSON="$SRC/mayhem/vendor/rapidjson/include"
INC="-I$SRC/cpp/inc -I$GEN -I$SCHEMA -I$RAPIDJSON"
DEF="-DBOND_LIB_TYPE=BOND_LIB_TYPE_STATIC"
STD="-std=c++14"
# FUZZ build opts: -DNDEBUG disables Bond's BOOST_ASSERT debug guards (e.g. typeid_value.h's
# `BOOST_ASSERT(false)` on an unexpected type tag) so the deserializer keeps running on malformed
# input and ASan reaches the real memory-safety bugs BEHIND those guards, instead of the fuzzer
# carpet-bombing on debug asserts. Stack-overflow protection is UNAFFECTED — Bond's RecursionGuard
# THROWS ExceededMaxRecursionDepthException (recursionguard.h), it is not an assert. -O1 speeds the
# fuzzer up. Oracle probe build below intentionally does NOT get these (kept as an honest round-trip).
FUZZOPT="-O1 -DNDEBUG"
LIBS="-lboost_thread -lboost_system -lpthread"
BUILD="$SRC/mayhem-build"
mkdir -p "$BUILD"

echo "== build.sh: SANITIZER_FLAGS=[$SANITIZER_FLAGS] DEBUG_FLAGS=[$DEBUG_FLAGS] =="

# Bond runtime translation units (precompiled sources + generated core types).
RT_SRCS=(
  "cpp/src/bond/core/select_protocol.cpp"
  "cpp/src/bond/core/value.cpp"
  "cpp/src/bond/core/parser.cpp"
  "cpp/src/bond/core/detail/typeid_value.cpp"
  "cpp/src/bond/protocol/detail/rapidjson_utils.cpp"
  "mayhem/generated/bond/core/bond_types.cpp"
  "mayhem/generated/bond/core/bond_const_types.cpp"
)

objname() { echo "$BUILD/$(echo "$1" | tr '/.' '__')$2.o"; }

# ---------------------------------------------------------------------------
# 1) Sanitized runtime + schema objects (fuzz build)
# ---------------------------------------------------------------------------
SAN_OBJS=()
for f in "${RT_SRCS[@]}"; do
  o="$(objname "$f" .san)"
  $CXX $STD $FUZZOPT $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $DEF $INC -c "$SRC/$f" -o "$o"
  SAN_OBJS+=("$o")
done
# ComplexTypes schema (the struct the harnesses deserialize into)
$CXX $STD $FUZZOPT $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $DEF $INC \
    -c "$SCHEMA/complex_types_types.cpp" -o "$BUILD/complex_types.san.o"
SAN_OBJS+=("$BUILD/complex_types.san.o")

# Standalone run-once driver (C file) — compiled once, linked per harness.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$BUILD/standalone_main.o"

build_target() {
  local name="$1"
  local hobj="$BUILD/$name.san.o"
  $CXX $STD $FUZZOPT $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $DEF $INC \
      -c "$SRC/mayhem/harnesses/$name.cpp" -o "$hobj"
  $CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      "$hobj" "${SAN_OBJS[@]}" $LIBS -o "/mayhem/$name"
  $CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS \
      "$BUILD/standalone_main.o" "$hobj" "${SAN_OBJS[@]}" $LIBS -o "/mayhem/$name-standalone"
}

build_target fuzz_compact_binary
build_target fuzz_fast_binary

# ---------------------------------------------------------------------------
# 2) Oracle probe — CLEAN build (NORMAL flags; NO sanitizer, NO -gdwarf-3),
#    dynamically linked so mayhem/test.sh's LD_PRELOAD sabotage shim can reach it.
#    Uses BasicTypes (simple scalars) for stable known-answer round-trips.
# ---------------------------------------------------------------------------
CLEAN_OBJS=()
for f in "${RT_SRCS[@]}"; do
  o="$(objname "$f" .clean)"
  $CXX $STD -O2 $DEF $INC -c "$SRC/$f" -o "$o"
  CLEAN_OBJS+=("$o")
done
$CXX $STD -O2 $DEF $INC -c "$SCHEMA/basic_types_types.cpp" -o "$BUILD/basic_types.clean.o"
CLEAN_OBJS+=("$BUILD/basic_types.clean.o")

$CXX $STD -O2 $DEF $INC "$SRC/mayhem/probes/roundtrip_probe.cpp" \
    "${CLEAN_OBJS[@]}" $LIBS -o /mayhem/roundtrip_probe

# Seed generator (clean build) — used offline to mint a format-valid starter seed per target.
$CXX $STD -O2 $DEF $INC "$SRC/mayhem/probes/seed_gen.cpp" \
    "${CLEAN_OBJS[@]}" $LIBS -o /mayhem/seed_gen

if ! file /mayhem/roundtrip_probe | grep -q 'dynamically linked'; then
  echo "FATAL: /mayhem/roundtrip_probe is not dynamically linked — oracle would be un-neuterable" >&2
  file /mayhem/roundtrip_probe >&2
  exit 1
fi

echo "== build.sh: OK =="
ls -l /mayhem/fuzz_compact_binary /mayhem/fuzz_compact_binary-standalone \
      /mayhem/fuzz_fast_binary /mayhem/fuzz_fast_binary-standalone \
      /mayhem/roundtrip_probe
