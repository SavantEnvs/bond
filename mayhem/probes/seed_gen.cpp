// Seed generator: serialize a populated BasicTypes with the requested binary
// protocol and write the raw bytes to stdout. Used once (offline) to produce a
// format-valid starter seed per fuzz target — a valid tagged Bond stream that
// the ComplexTypes reader parses (unknown field ids are skipped), giving the
// fuzzer real structural framing to mutate from. Not part of the fuzz build.
//
// (BasicTypes is used rather than ComplexTypes because a default ComplexTypes
// carries an empty bonded<> field that cannot itself be serialized.)
//
// usage: seed_gen <compact|fast> > seed.bin
#include "basic_types_reflection.h"

#include <bond/core/bond.h>
#include <bond/protocol/compact_binary.h>
#include <bond/protocol/fast_binary.h>
#include <bond/stream/output_buffer.h>

#include <cstring>
#include <unistd.h>

static tests::BasicTypes MakePopulated()
{
    tests::BasicTypes obj;
    obj._bool = true;
    obj._str = "hello";
    obj._wstr = L"world";
    obj._uint64 = 12345678901234ULL;
    obj._uint32 = 3000000000u;
    obj._int32 = -2000000000;
    obj._int64 = -9000000000000LL;
    obj._double = 3.5;
    obj._float = 1.25f;
    return obj;
}

template <typename Writer>
static void Emit(const tests::BasicTypes& obj)
{
    bond::OutputBuffer output;
    Writer writer(output);
    bond::Serialize(obj, writer);

    bond::blob data = output.GetBuffer();
    const char* p = static_cast<const char*>(data.content());
    ssize_t n = static_cast<ssize_t>(data.length());
    ssize_t off = 0;
    while (off < n) {
        ssize_t w = write(1, p + off, n - off);
        if (w <= 0) break;
        off += w;
    }
}

int main(int argc, char** argv)
{
    const char* proto = argc > 1 ? argv[1] : "compact";
    tests::BasicTypes obj = MakePopulated();
    if (std::strcmp(proto, "fast") == 0)
        Emit<bond::FastBinaryWriter<bond::OutputBuffer> >(obj);
    else
        Emit<bond::CompactBinaryWriter<bond::OutputBuffer> >(obj);
    return 0;
}
