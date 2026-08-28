// libFuzzer harness: Bond Fast Binary deserializer over untrusted bytes.
//
// Identical shape to fuzz_compact_binary but exercises the Fast Binary tagged
// protocol reader. Malformed input throws and returns 0; only ASan/UBSan
// faults are findings.
#include "complex_types_reflection.h"

#include <bond/core/bond.h>
#include <bond/protocol/fast_binary.h>
#include <bond/stream/input_buffer.h>

#include <cstddef>
#include <cstdint>
#include <exception>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    if (size > (1u << 24)) {
        return 0;
    }
    try {
        bond::InputBuffer input(data, static_cast<uint32_t>(size));
        bond::FastBinaryReader<bond::InputBuffer> reader(input);
        tests::ComplexTypes obj;
        bond::Deserialize(reader, obj);
    } catch (const std::exception&) {
    } catch (...) {
    }
    return 0;
}
