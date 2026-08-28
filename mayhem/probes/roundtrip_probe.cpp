// Behavioral-oracle probe (clean build, dynamically linked).
//
// Serializes a fixed BasicTypes value with the requested binary protocol, then
// deserializes it back and prints ONE requested field. This is a known-answer
// round-trip through Bond's real (de)serializer: if the code is neutered to a
// no-op / exit(0) (the verify-repo sabotage shim), it prints nothing and the
// test.sh assertions fail.
//
// usage: roundtrip_probe <protocol> <field>
//   protocol: compact | fast
//   field:    bool | str | wstr | uint64 | int32 | double | float
#include "basic_types_reflection.h"

#include <bond/core/bond.h>
#include <bond/protocol/compact_binary.h>
#include <bond/protocol/fast_binary.h>
#include <bond/stream/input_buffer.h>
#include <bond/stream/output_buffer.h>

#include <cstdio>
#include <cstring>
#include <string>

static tests::BasicTypes MakeKnown()
{
    tests::BasicTypes obj;
    obj._bool = true;
    obj._str = "hello";
    obj._wstr = L"world";
    obj._uint64 = 12345678901234ULL;
    obj._uint16 = 4242;
    obj._uint32 = 3000000000u;
    obj._uint8 = 200;
    obj._int8 = -42;
    obj._int16 = -12345;
    obj._int32 = -2000000000;
    obj._int64 = -9000000000000LL;
    obj._double = 3.5;
    obj._float = 1.25f;
    return obj;
}

template <typename Writer, typename Reader>
static tests::BasicTypes RoundTrip(const tests::BasicTypes& in)
{
    bond::OutputBuffer output;
    Writer writer(output);
    bond::Serialize(in, writer);

    bond::blob data = output.GetBuffer();
    bond::InputBuffer input(data);
    Reader reader(input);

    tests::BasicTypes out;
    bond::Deserialize(reader, out);
    return out;
}

int main(int argc, char** argv)
{
    const char* proto = argc > 1 ? argv[1] : "compact";
    const char* field = argc > 2 ? argv[2] : "str";

    tests::BasicTypes in = MakeKnown();
    tests::BasicTypes out;

    if (std::strcmp(proto, "fast") == 0) {
        out = RoundTrip<bond::FastBinaryWriter<bond::OutputBuffer>,
                        bond::FastBinaryReader<bond::InputBuffer> >(in);
    } else {
        out = RoundTrip<bond::CompactBinaryWriter<bond::OutputBuffer>,
                        bond::CompactBinaryReader<bond::InputBuffer> >(in);
    }

    if (std::strcmp(field, "bool") == 0)        std::printf("%d\n", out._bool ? 1 : 0);
    else if (std::strcmp(field, "str") == 0)    std::printf("%s\n", out._str.c_str());
    else if (std::strcmp(field, "uint64") == 0) std::printf("%llu\n", (unsigned long long)out._uint64);
    else if (std::strcmp(field, "uint32") == 0) std::printf("%u\n", out._uint32);
    else if (std::strcmp(field, "int32") == 0)  std::printf("%d\n", out._int32);
    else if (std::strcmp(field, "int64") == 0)  std::printf("%lld\n", (long long)out._int64);
    else if (std::strcmp(field, "double") == 0) std::printf("%g\n", out._double);
    else if (std::strcmp(field, "float") == 0)  std::printf("%g\n", (double)out._float);
    else { std::fprintf(stderr, "unknown field %s\n", field); return 2; }

    return 0;
}
