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

def very_high_level_monpro(a, b, n):
    return a * b * pow(1 << R_BITS, -1, n) % n

n = 0x99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D

A = random.getrandbits(256)
B = random.getrandbits(256)
print("A:", hex(A))
print("B:", hex(B))
print("R:", hex(very_high_level_monpro(A, B, n)))

# A = 0x7b2c2cff3781db07b42ff01e242a6cfe7ef25a57c9491d84cb72a139c3897b63
# B = 0xf89aec4f5d4fab3f990d9124b40120839f8e068c36f94daf6cbd33e0955a2211
# print("A:", hex(A))
# print("B:", hex(B))
# print("R:", hex(very_high_level_monpro(A, B, n)))

# a1 = 0x4ED76052036851F7142CF1783B7F82D348D9B8E3E2DC4276B0CAD4E78F674692
# b1 = 0x77802675A284891B1C4633B913C659389057BF74123211F5EAB6C841E624A906
# a2 = 0x69ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567
# b2 = 0x6EDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210
# print(hex(monpro_hr(a1, b1, n)))
# print(hex(very_high_level_monpro(a1, b1, n)))
# print(hex(monpro_hr(a2, b2, n)))
# print(hex(very_high_level_monpro(a2, b2, n)))

