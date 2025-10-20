#BINARY MONTGOMERY
import random
R_BITS = 256
R = 1 << R_BITS


# montgomery redcution, part of monpro
# REDC(T) = T * R^{-1} mod n, for R = 2^R_bits
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
    T = a_bar * b_bar
    return montgomery_redc(T, n)


# Conversions to/from Montgomery domain
#a_bar = a * R mod n, with R = 2^R_bits
def to_montgomery(a, n):
    return (a << R_BITS) % n

#a = a_bar * R^{-1} mod n = REDC(a_bar)
def from_montgomery(a_bar, n):
    return montgomery_redc(a_bar, n)

# -----------------------------
# VLNW schedule generator
# -----------------------------
def vlnw_schedule(exponent: int, d: int = 4):
    """
    Generate VLNW windows from exponent (LSB -> MSB)
    Returns a list of (window_value, window_length) from LSB first
    """
    e_bits = bin(exponent)[2:][::-1]  # LSB first
    schedule = []
    i = 0
    while i < len(e_bits):
        if e_bits[i] == '0':
            # Zero window of length 1
            schedule.append((0, 1))
            i += 1
        else:
            # Non-zero window of length d or remaining bits
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
    """
    Compute all odd powers M^w for w = 1,3,...,2^d-1
    using only MonPro and M^2.
    """
    max_w = (1 << d) - 1
    powers = {1: base_bar}
    M2 = monpro(base_bar, base_bar, modulus)

    # Compute remaining odd powers iteratively
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

    # Precompute odd powers
    powers = precompute_base_powers(base_bar, modulus, d)
    schedule = vlnw_schedule(exponent, d)

    acc = one_bar
    # Process windows from MSB → LSB
    for win_val, win_len in reversed(schedule):
        for _ in range(win_len):
            acc = monpro(acc, acc, modulus)  # square
        if win_val != 0:
            acc = monpro(acc, powers[win_val], modulus)  # multiply by precomputed

    return from_montgomery(acc, modulus)

# Modular exponentiation using Montgomery multiplication
def montgomery_pow(base, exponent, modulus):
    if modulus == 1:
        return 0
    
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


# -----------------------------
# Simple test
# -----------------------------
if __name__ == "__main__":
    # Generate a 256-bit modulus (prime for RSA would be better)
    # n = random.getrandbits(256) | (1 << 255) | 1  # ensure 256-bit, odd
    M = random.getrandbits(255)
    # exp = random.getrandbits(256) | 1  # exponent, 256-bit, odd 
    
    key_n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
    key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
    key_e = 0x0000000000000000000000000000000000000000000000000000000000010001

    print("Original M:", M)
    print("Testing VLNW vs Binary Montgomery for 256-bit numbers...")
    C_bin = montgomery_pow(M, key_e, key_n)
    C_vlnw = montgomery_pow_vlnw(M, key_e, key_n, d=4)
    print("Binary Montgomery:", C_bin)
    print("VLNW Montgomery:  ", C_vlnw)
    assert C_bin == C_vlnw, "VLNW does not match binary Montgomery!"

    # Test decryption-like double exponentiation
    M_bin = montgomery_pow(C_bin, key_d, key_n)
    M_vlnw = montgomery_pow_vlnw(C_vlnw, key_d, key_n, d=4)
    print("Binary Montgomery M_bin:", M_bin)
    print("VLNW Montgomery M_vlnw:", M_vlnw)
    assert M_bin == M_vlnw, "VLNW double exponentiation failed!"
    assert M_vlnw == M, "Encryption/decryption failed!"

    print("256-bit VLNW test passed!")