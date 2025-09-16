# Binary (bit-serial) Montgomery modular exponentiation with fixed 256-bit words.
# - Assumes: modulus n is odd and fits in 256 bits
# - Uses: R = 2^256, classic "if T is odd add n, then shift" REDC loop.

#BINARY MONTGOMERY

from typing import Tuple

R_BITS = 256
R = 1 << R_BITS


# montgomery redcution, part of monpro
# REDC(T) = T * R^{-1} mod n, for R = 2^R_bits
def montgomery_redc(T: int, n: int) -> int:
    for _ in range(R_BITS):
        if T & 1:
            T = (T + n) >> 1
        else:
            T >>= 1
    if T >= n:
        T -= n
    return T

# MonPro(a, b) = a * b * R^{-1} mod n
def monpro(a_bar: int, b_bar: int, n: int) -> int:
    T = a_bar * b_bar
    return montgomery_redc(T, n)


# Conversions to/from Montgomery domain
#a_bar = a * R mod n, with R = 2^R_bits
def to_montgomery(a: int, n: int) -> int:
    return (a << R_BITS) % n

#a = a_bar * R^{-1} mod n = REDC(a_bar)
def from_montgomery(a_bar: int, n: int) -> int:
    return montgomery_redc(a_bar, n)


# Modular exponentiation using Montgomery multiplication
def montgomery_pow(base: int, exponent: int, modulus: int) -> int:
    if modulus == 1:
        return 0
    if exponent < 0:
        raise ValueError("Negative exponents not supported in this simple model.")
    # Fixed-size constraints

    base %= modulus
    if exponent == 0:
        return 1 % modulus

    # Domain conversion
    one_bar  = to_montgomery(1,    modulus)
    base_bar = to_montgomery(base, modulus)

    # L→R binary exponentiation
    acc = one_bar # the accumulator is P
    for bit in reversed(range(exponent.bit_length())):
        acc = monpro(acc, acc, modulus)  # square
        if (exponent >> bit) & 1:
            acc = monpro(acc, base_bar, modulus)  # multiply

    # Convert back
    return from_montgomery(acc, modulus)

# ---------- tiny self-check ----------
if __name__ == "__main__":
    # Random-ish small tests (Python bigints make this easy)
    tests = [
        (5, 117, (1<<256) - 189),       # odd 256-bit-ish modulus
        (2, 1000, (1<<255) | 1),        # odd
        (123456789, 987654321, (1<<200) | 1),
    ]
    for a, e, n in tests:
        assert (n & 1) == 1 and n < (1<<256)
        got = montgomery_pow(a, e, n)
        ref = pow(a, e, n)
        assert got == ref, f"mismatch for ({a},{e},n): got {got}, ref {ref}"
    print("Fixed-256 Montgomery: all tests passed ✔")
