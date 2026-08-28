// libFuzzer harness: Bond Compact Binary deserializer over untrusted bytes.
//
// Reads fuzzer-provided bytes into a bond::InputBuffer, wraps them in a
// CompactBinaryReader, and Deserialize()s into a compile-time ComplexTypes
// struct (lists, sets, vector<blob>, nullable, map, bonded<>) — the richest
// self-contained schema Bond ships pre-generated. Malformed input throws a
// bond::Exception (or std::exception); that is EXPECTED and returns 0. Only a
// memory-safety fault (ASan) or UB (UBSan) is a finding.
#include "complex_types_reflection.h"

#include <bond/core/bond.h>
#include <bond/protocol/compact_binary.h>
#include <bond/stream/input_buffer.h>

#include <cstddef>
#include <cstdint>
#include <exception>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    if (size > (1u << 24)) {
        return 0;  // keep single inputs bounded
    }
    try {
        bond::InputBuffer input(data, static_cast<uint32_t>(size));
        bond::CompactBinaryReader<bond::InputBuffer> reader(input);
        tests::ComplexTypes obj;
        bond::Deserialize(reader, obj);
    } catch (const std::exception&) {
        // malformed input rejected by the deserializer — not a finding
    } catch (...) {
        // bond::CoreException etc.
    }
    return 0;
}
