# HIGH-RADIX MONTGOMERY WITH VLNW
import random

# -----------------------------
# PARAMETERS
# -----------------------------
R_BITS = 256          # modulus length in bits
WORD_BITS = 32        # high-radix word size
R = 1 << R_BITS

# Global multiplication counter
mul_count = 0

# -----------------------------
# Helpers
# -----------------------------
def int_to_words(x, w=WORD_BITS):
    """Split integer into list of w-bit words, LSB first."""
    words = []
    mask = (1 << w) - 1
    while x:
        words.append(x & mask)
        x >>= w
    return words or [0]

def words_to_int(words, w=WORD_BITS):
    """Combine list of w-bit words into integer."""
    x = 0
    for i in reversed(range(len(words))):
        x = (x << w) | words[i]
    return x

def modinv(a, m):
    """Modular inverse using extended Euclidean algorithm."""
    g, x, y = extended_gcd(a, m)
    if g != 1:
        raise ValueError("No modular inverse")
    return x % m

def extended_gcd(a, b):
    """Extended GCD algorithm."""
    if b == 0:
        return a, 1, 0
    g, y, x = extended_gcd(b, a % b)
    y -= (a // b) * x
    return g, x, y

# -----------------------------
# High-Radix Montgomery Multiplication
# -----------------------------
def monpro_hr(a_bar, b_bar, n, w=WORD_BITS):
    """
    High-Radix Montgomery multiplication:
    Computes a_bar * b_bar * R^-1 mod n
    """
    global mul_count
    mul_count += 1

    # Precompute n0_inv = -n0^-1 mod 2^w
    n0 = n & ((1 << w) - 1)
    n0_inv = (-modinv(n0, 1 << w)) & ((1 << w) - 1)
    A = int_to_words(a_bar, w)
    B = int_to_words(b_bar, w)
    s = len(A)
    u = 0

    for i in range(s):
        Ai = A[i]
        # Multiply-add step
        u += Ai * b_bar
        u0 = u & ((1 << w) - 1)
        m = (u0 * n0_inv) & ((1 << w) - 1)
        u += m * n
        u >>= w

    if u >= n:
        u -= n
    return u

# -----------------------------
# Conversions to/from Montgomery domain
# -----------------------------
def to_montgomery(a, n):
    return (a << R_BITS) % n

def from_montgomery(a_bar, n):
    return monpro_hr(a_bar, 1, n)  # multiply by 1 in HR-MonPro

# -----------------------------
# VLNW schedule generator
# -----------------------------
def vlnw_schedule(exponent: int, d):
    d = 4
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
    print(schedule)
    print(len(schedule))

    return schedule

# -----------------------------
# Precompute odd powers of base
# -----------------------------
def precompute_base_powers(base_bar, modulus, d):
    max_w = (1 << d) - 1
    powers = {1: base_bar}
    M2 = monpro_hr(base_bar, base_bar, modulus)
    for w in range(3, max_w + 1, 2):
        powers[w] = monpro_hr(powers[w - 2], M2, modulus)
    return powers

# -----------------------------
# VLNW Montgomery exponentiation (High-Radix)
# -----------------------------
def montgomery_pow_vlnw_hr(msgin_data, exponent, modulus, d):
    if modulus == 1:
        return 0
    if exponent == 0:
        return 1 % modulus

    one_bar  = to_montgomery(1, modulus)
    msgin_data_bar = to_montgomery(msgin_data, modulus)

    powers = precompute_base_powers(msgin_data_bar, modulus, d)
    schedule = vlnw_schedule(exponent, d)

    acc = one_bar
    for win_val, win_len in reversed(schedule):
        print(win_len)
        for _ in range(win_len):
            acc = monpro_hr(acc, acc, modulus)  # square
        if win_val != 0:
            acc = monpro_hr(acc, powers[win_val], modulus)  # multiply

    return from_montgomery(acc, modulus)

# -----------------------------
# -----------------------------
# TEST
# -----------------------------
# if __name__ == "__main__":
#     # Example 256-bit RSA modulus and exponents
#     key_n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
#     key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
#     key_e = 0x0000000000000000000000000000000000000000000000000000000000010001

#     test_key = random.getrandbits(256)
#     # Random message
#     M = random.getrandbits(255)

#     print("Original M:", M)
#     print("Testing VLNW high-radix Montgomery (w={} bits)...".format(WORD_BITS))

#     # Encryption
#     mul_count = 0
#     C = montgomery_pow_vlnw_hr(M, key_e, key_n, 4)
#     print("Ciphertext C:", C)
#     print("Multiplications:", mul_count)

#     # Decryption
#     mul_count = 0
#     M_dec = montgomery_pow_vlnw_hr(C, key_d, key_n, 4)
#     print("Decrypted M:", M_dec)
#     print("Multiplications:", mul_count)

#     assert M_dec == M, "High-radix VLNW failed!"
#     print("High-radix VLNW test passed!")

def precompute_R2_modn__and_n0_prime(key_n):
  R = 1 << 256
  w = 32
  n0 = key_n & ((1 << w) - 1)
  n0_inv = (-modinv(n0, 1 << w)) & ((1 << w) - 1)
  return R**2 % key_n, n0_inv

# constants:
n_prime = 2285093819
n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d

A = 0x89ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567
B = 0xFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210

abar = to_montgomery(int(A), int(n))
bbar = to_montgomery(int(B), int(n))
pbar = monpro_hr(abar, bbar, int(n))
p_fin = from_montgomery(pbar, int(n))

check = int(A) * int(B) % int(n)
print(p_fin)
print(check)