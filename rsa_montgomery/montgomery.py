# Binary (bit-serial) Montgomery modular exponentiation with fixed 256-bit words.
# - Assumes: modulus n is odd and fits in 256 bits
# - Uses: R = 2^256, classic "if T is odd add n, then shift" REDC loop.

from typing import Tuple

R_BITS = 256
R = 1 << R_BITS

def montgomery_setup_fixed(n: int) -> Tuple[int, int]:
    """
    Fixed-size setup for 256-bit datapath.
    Returns (R_BITS, R). Validates that n is odd and < 2^256.
    """
    if n <= 0 or (n & 1) == 0:
        raise ValueError("Modulus n must be a positive odd integer.")
    if n >= R:
        raise ValueError("Modulus n must fit in 256 bits (n < 2^256).")
    return R_BITS, R

def montgomery_redc_bin(T: int, n: int, R_bits: int = R_BITS) -> int:
    """
    Binary Montgomery reduction:
      REDC(T) = T * R^{-1} mod n, for R = 2^R_bits (here R_bits=256).
    Preconditions: n odd, 0 <= T, and final result < n.
    """
    for _ in range(R_bits):
        if T & 1:
            T = (T + n) >> 1
        else:
            T >>= 1
    if T >= n:
        T -= n
    return T

def to_montgomery(a: int, n: int, R_bits: int = R_BITS) -> int:
    """
    a_bar = a * R mod n, with R = 2^R_bits.
    """
    # R is 2^R_bits, so a*R = a << R_bits
    return (a << R_bits) % n

def from_montgomery(a_bar: int, n: int, R_bits: int = R_BITS) -> int:
    """
    a = a_bar * R^{-1} mod n = REDC(a_bar).
    """
    return montgomery_redc_bin(a_bar, n, R_bits)

def montgomery_mul_bin(a_bar: int, b_bar: int, n: int, R_bits: int = R_BITS) -> int:
    """
    c_bar = a_bar * b_bar * R^{-1} mod n = REDC(a_bar * b_bar).
    """
    T = a_bar * b_bar
    return montgomery_redc_bin(T, n, R_bits)

def montgomery_pow_bin(base: int, exponent: int, modulus: int) -> int:
    """
    Computes base^exponent mod modulus using Montgomery (binary REDC), fixed R=2^256.
    - modulus must be odd and < 2^256
    - left-to-right square-and-multiply in Montgomery domain
    """
    if modulus == 1:
        return 0
    if exponent < 0:
        raise ValueError("Negative exponents not supported in this simple model.")
    # Fixed-size constraints
    R_bits, _ = montgomery_setup_fixed(modulus)

    base %= modulus
    if exponent == 0:
        return 1 % modulus

    # Domain conversion
    one_bar  = to_montgomery(1,    modulus, R_bits)
    base_bar = to_montgomery(base, modulus, R_bits)

    # L→R binary exponentiation
    acc = one_bar # the accumulator is P
    for bit in reversed(range(exponent.bit_length())):
        acc = montgomery_mul_bin(acc, acc, modulus, R_bits)  # square
        if (exponent >> bit) & 1:
            acc = montgomery_mul_bin(acc, base_bar, modulus, R_bits)  # multiply

    # Convert back
    return from_montgomery(acc, modulus, R_bits)

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
        got = montgomery_pow_bin(a, e, n)
        ref = pow(a, e, n)
        assert got == ref, f"mismatch for ({a},{e},n): got {got}, ref {ref}"
    print("Fixed-256 Montgomery: all tests passed ✔")
