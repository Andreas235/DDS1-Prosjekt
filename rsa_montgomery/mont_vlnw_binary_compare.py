#BINARY MONTGOMERY
import random

R_BITS = 256
R = 1 << R_BITS

# Global multiplication counter
mul_count = 0

# montgomery redcution, part of monpro
def montgomery_redc(T, n):
    for _ in range(R_BITS):
        if T & 1:
            T = (T + n) >> 1
        else:
            T >>= 1
    if T >= n:
        T -= n
    return T

# MonPro(a, b) = a * b * R^{-1} mod n
def monpro(a_bar, b_bar, n):
    global mul_count
    mul_count += 1
    T = a_bar * b_bar
    return montgomery_redc(T, n)

# Conversions to/from Montgomery domain
def to_montgomery(a, n):
    return (a << R_BITS) % n

def from_montgomery(a_bar, n):
    return montgomery_redc(a_bar, n)

# -----------------------------
# VLNW schedule generator
# -----------------------------
def vlnw_schedule(exponent: int, d: int = 4):
    e_bits = bin(exponent)[2:][::-1]  # LSB first
    schedule = []
    i = 0
    while i < len(e_bits):
        if e_bits[i] == '0':
            schedule.append((0, 1))
            i += 1
        else:
            win_len = min(d, len(e_bits) - i)
            val = 0
            for j in range(win_len):
                val |= (int(e_bits[i + j]) << j)
            schedule.append((val, win_len))
            i += win_len
    return schedule

# -----------------------------
# Precompute odd powers of base
# -----------------------------
def precompute_base_powers(base_bar, modulus, d=4):
    max_w = (1 << d) - 1
    powers = {1: base_bar}
    M2 = monpro(base_bar, base_bar, modulus)
    for w in range(3, max_w + 1, 2):
        powers[w] = powers[w - 2]
        powers[w] = monpro(powers[w], M2, modulus)
    return powers

# -----------------------------
# VLNW Montgomery exponentiation
# -----------------------------
def montgomery_pow_vlnw(base, exponent, modulus, d=4):
    if modulus == 1:
        return 0
    base %= modulus
    if exponent == 0:
        return 1 % modulus

    one_bar  = to_montgomery(1, modulus)
    base_bar = to_montgomery(base, modulus)

    powers = precompute_base_powers(base_bar, modulus, d)
    schedule = vlnw_schedule(exponent, d)

    acc = one_bar
    for win_val, win_len in reversed(schedule):
        for _ in range(win_len):
            acc = monpro(acc, acc, modulus)
        if win_val != 0:
            acc = monpro(acc, powers[win_val], modulus)

    return from_montgomery(acc, modulus)

# -----------------------------
# Binary Montgomery exponentiation
# -----------------------------
def montgomery_pow(base, exponent, modulus):
    if modulus == 1:
        return 0
    base %= modulus
    if exponent == 0:
        return 1 % modulus

    one_bar  = to_montgomery(1, modulus)
    base_bar = to_montgomery(base, modulus)

    acc = one_bar
    for bit in reversed(range(exponent.bit_length())):
        acc = monpro(acc, acc, modulus)
        if (exponent >> bit) & 1:
            acc = monpro(acc, base_bar, modulus)

    return from_montgomery(acc, modulus)

# -----------------------------
# Test with multiplication counting
# -----------------------------
if __name__ == "__main__":
    key_n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
    key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
    key_e = 0x0000000000000000000000000000000000000000000000000000000000010001
    M = random.getrandbits(255)

    print("Original M:", M)

    # Binary Montgomery
    mul_count = 0
    C_bin = montgomery_pow(M, key_d, key_n)
    print("Binary Montgomery result:", C_bin)
    print("Binary Montgomery multiplications:", mul_count)

    # VLNW Montgomery
    mul_count = 0
    C_vlnw = montgomery_pow_vlnw(M, key_d, key_n, d=4)
    print("VLNW Montgomery result:  ", C_vlnw)
    print("VLNW Montgomery multiplications:", mul_count)

    assert C_bin == C_vlnw, "VLNW does not match binary Montgomery!"
