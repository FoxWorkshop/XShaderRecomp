#!/usr/bin/env python3
"""Reimplementation of rapidhash in Python.

rapidhash64 derives the 64-bit program key (ShaderVariantKey) for every
generated variant; which is then used by the source code to fetch the
compiled shaders.

first:
    hash(state) -> variantKey

then:
    variantKey -> compiledShader

Ported from original thirdparty/rapidhash/rapidhash.h (default seed, compact mode,
little-endian). Must stay in sync with rapidhash updates.

The variantKey is used in the shader pipeline cache. So ideally, never change this;
so user doesn't get stutter on cache rebuild.

Usage:
- python3 variant_hash.py  (runs the known-answer self-test)
"""

_SECRET = (
    0x2D358DCCAA6C78A5, 0x8BB84B93962EACC9, 0x4B33A62ED433D4A3, 0x4D5A2DA51DE1AA47,
    0xA0761D6478BD642F, 0xE7037ED1A0B428DB, 0x90ED1765281C388C, 0xAAAAAAAAAAAAAAAA,
)

_MASK64 = 0xFFFFFFFFFFFFFFFF


def _mix(a, b):
    """Xors the low and high 64-bit halves of the 128-bit product a * b."""
    product = a * b
    return (product & _MASK64) ^ (product >> 64)


def _read32(data, offset):
    return int.from_bytes(data[offset:offset + 4], "little")


def _read64(data, offset):
    return int.from_bytes(data[offset:offset + 8], "little")


def _rapidhash(data):
    """Hashes data exactly like C++ rapidhash(key, len) with the default seed."""
    secret = _SECRET
    seed = 0
    seed ^= _mix(seed ^ secret[2], secret[1])
    a = b = 0
    remaining = len(data)
    offset = 0
    if remaining <= 16:
        if remaining >= 4:
            seed ^= remaining
            if remaining >= 8:
                a = _read64(data, 0)
                b = _read64(data, remaining - 8)
            else:
                a = _read32(data, 0)
                b = _read32(data, remaining - 4)
        elif remaining > 0:
            a = (data[0] << 45) | data[remaining - 1]
            b = data[remaining >> 1]
    else:
        see1 = see2 = see3 = see4 = see5 = see6 = seed
        if remaining > 112:
            # Consume 112-byte blocks, then fold the six lane seeds in.
            while remaining > 112:
                seed = _mix(_read64(data, offset) ^ secret[0], _read64(data, offset + 8) ^ seed)
                see1 = _mix(_read64(data, offset + 16) ^ secret[1], _read64(data, offset + 24) ^ see1)
                see2 = _mix(_read64(data, offset + 32) ^ secret[2], _read64(data, offset + 40) ^ see2)
                see3 = _mix(_read64(data, offset + 48) ^ secret[3], _read64(data, offset + 56) ^ see3)
                see4 = _mix(_read64(data, offset + 64) ^ secret[4], _read64(data, offset + 72) ^ see4)
                see5 = _mix(_read64(data, offset + 80) ^ secret[5], _read64(data, offset + 88) ^ see5)
                see6 = _mix(_read64(data, offset + 96) ^ secret[6], _read64(data, offset + 104) ^ see6)
                offset += 112
                remaining -= 112
            seed ^= see1
            see2 ^= see3
            see4 ^= see5
            seed ^= see6
            see2 ^= see4
            seed ^= see2
        # Tail below 112 bytes, then the last 16 bytes salted with the length.
        if remaining > 16:
            seed = _mix(_read64(data, offset) ^ secret[2], _read64(data, offset + 8) ^ seed)
            if remaining > 32:
                seed = _mix(_read64(data, offset + 16) ^ secret[2], _read64(data, offset + 24) ^ seed)
                if remaining > 48:
                    seed = _mix(_read64(data, offset + 32) ^ secret[1], _read64(data, offset + 40) ^ seed)
                    if remaining > 64:
                        seed = _mix(_read64(data, offset + 48) ^ secret[1], _read64(data, offset + 56) ^ seed)
                        if remaining > 80:
                            seed = _mix(_read64(data, offset + 64) ^ secret[2], _read64(data, offset + 72) ^ seed)
                            if remaining > 96:
                                seed = _mix(_read64(data, offset + 80) ^ secret[1], _read64(data, offset + 88) ^ seed)
        a = _read64(data, offset + remaining - 16) ^ remaining
        b = _read64(data, offset + remaining - 8)
    a ^= secret[1]
    b ^= seed
    product = a * b
    a = product & _MASK64
    b = product >> 64
    return _mix(a ^ secret[7], b ^ secret[1] ^ remaining)


def rapidhash64(values):
    """rapidhash 64-bit hash over values as little-endian uint32 words.

    Zero maps to 1 to keep 0 reserved for GenericShaderVariant."""
    data = b"".join(value.to_bytes(4, "little") for value in values)
    return _rapidhash(data) or 1


def _self_test():
    """Known-answer tests covering every input-length branch.

    Expected values come from the vendored rapidhash.h, compiled and
    run on the same bytes."""
    assert rapidhash64(()) == 0x0338DC4BE2CECDAE
    assert rapidhash64((1,)) == 0x2B281F986C8B17D6
    assert rapidhash64((1, 2)) == 0x74CCB11E757C8BD9
    assert rapidhash64((1, 2, 3, 4)) == 0x7B00637CAECBFBF5
    assert rapidhash64(tuple(range(1, 9))) == 0xCD9EB5B54E179289
    assert rapidhash64(tuple(range(1, 14))) == 0xB98223557BBB120F
    assert rapidhash64(tuple(range(1, 18))) == 0xD3ED8BCC65590BF0
    assert rapidhash64(tuple(range(1, 22))) == 0x4A9084E9CD81CD21
    assert rapidhash64(tuple(range(1, 27))) == 0x5B76533A098DA795
    assert rapidhash64(tuple(range(1, 29))) == 0xAD9E2C4851542E6C
    assert rapidhash64(tuple(range(1, 30))) == 0x490180BF03A7413A
    assert rapidhash64(tuple(range(1, 42))) == 0x86B4D3FA9B255048
    assert rapidhash64(tuple(range(1, 58))) == 0x5B519FDC4CE91CFA
    assert rapidhash64(tuple(range(1, 59))) == 0x32F4DF6A887BDD39
    assert rapidhash64(tuple(range(1, 85))) == 0x152FC2A30D2153EB
    assert rapidhash64(tuple(range(1, 86))) == 0xA16161128B233C8E

    print("variant_hash: 16 known-answer tests passed")


if __name__ == "__main__":
    _self_test()
