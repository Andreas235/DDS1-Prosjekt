# HIGH-RADIX (w=32) VLNW MONTGOMERY
import random

R_BITS = 256
R = 1 << R_BITS
W_BITS = 32
W_MASK = (1 << W_BITS) - 1
S_WORDS = R_BITS // W_BITS  # 256/32 = 8 words

# Global multiplication counter
mul_count = 0

# -----------------------------
# HIGH-RADIX MONTGOMERY REDC
# -----------------------------
def montgomery_redc_highradix(T, n):
    """High-radix Montgomery reduction, w=32"""
    for _ in range(S_WORDS):
        u0 = T & W_MASK
        n0_inv = pow(n & W_MASK, -1, 1 << W_BITS)  # n0^-1 mod 2^w
        m = (u0 * n0_inv) & W_MASK
        T = (T + m * n) >> W_BITS
    if T >= n:
        T -= n
    return T

def monpro_highradix(a_bar, b_bar, n):
    global mul_count
    mul_count += 1
    T = a_bar * b_bar
    return montgomery_redc_highradix(T, n)

# -----------------------------
# Conversions to/from Montgomery domain
# -----------------------------
def to_montgomery(a, n):
    return (a << R_BITS) % n

def from_montgomery(a_bar, n):
    return montgomery_redc_highradix(a_bar, n)

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
    M2 = monpro_highradix(base_bar, base_bar, modulus)
    for w in range(3, max_w + 1, 2):
        powers[w] = powers[w - 2]
        powers[w] = monpro_highradix(powers[w], M2, modulus)
    return powers

# -----------------------------
# VLNW High-Radix Montgomery exponentiation
# -----------------------------
def montgomery_pow_vlnw_highradix(base, exponent, modulus, d=4):
    if modulus == 1:
        return 0
    base %= modulus
    if exponent == 0:
        return 1 % modulus

    one_bar  = to_montgomery(1, modulus)
    base_bar = to_montgomery(base, modulus)

    # Precompute odd powers
    powers = precompute_base_powers(base_bar, modulus, d)
    schedule = vlnw_schedule(exponent, d)

    acc = one_bar
    for win_val, win_len in reversed(schedule):
        for _ in range(win_len):
            acc = monpro_highradix(acc, acc, modulus)  # square
        if win_val != 0:
            acc = monpro_highradix(acc, powers[win_val], modulus)  # multiply

    return from_montgomery(acc, modulus)

# -----------------------------
# Simple test
# -----------------------------
if __name__ == "__main__":
    # Random 256-bit message
    M = random.getrandbits(255)

    key_n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
    key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
    key_e = 0x0000000000000000000000000000000000000000000000000000000000010001

    print("Original M:", M)
    print("Testing VLNW high-radix (w=32) Montgomery for 256-bit numbers...")

    mul_count = 0
    C_vlnw = montgomery_pow_vlnw_highradix(M, key_e, key_n, d=4)
    print("VLNW High-Radix Montgomery C:", C_vlnw)
    print("VLNW High-Radix multiplications:", mul_count)

    # Decryption-like check
    mul_count = 0
    M_vlnw = montgomery_pow_vlnw_highradix(C_vlnw, key_d, key_n, d=4)
    print("VLNW High-Radix Montgomery M_vlnw:", M_vlnw)
    print("Multiplications (decryption):", mul_count)

    assert M_vlnw == M, "High-Radix VLNW encryption/decryption failed!"
    print("256-bit High-Radix VLNW test passed!")
