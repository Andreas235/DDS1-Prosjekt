# montgomery_fixed.py — binary Montgomery (k = 256) with to/from via monpro
# RL (right-to-left) binary exponentiation

R_BITS = 256
R = 1 << R_BITS

def montgomery_redc(T, n):
    """Binary REDC: returns T * R^{-1} mod n, with R = 2^256."""
    for _ in range(R_BITS):
        if T & 1:
            T = (T + n) >> 1
        else:
            T >>= 1
    if T >= n:
        T -= n
    return T

def monpro(a, b, n):
    """
    Montgomery product: MonPro(a,b) = a*b*R^{-1} mod n.
    Works whether a/b are in Montgomery domain, or when using R^2 mod n for entry.
    """
    T = a * b
    return montgomery_redc(T, n)

def precompute_R2_mod_n(n):
    """Compute R^2 mod n once (hardware: store in a register)."""
    r_mod = R % n
    return (r_mod * r_mod) % n

# --- Conversions via MonPro ---

def to_montgomery(a, n):
    """a_bar = a * R mod n = MonPro(a, R^2 mod n)."""
    R2 = precompute_R2_mod_n(n)
    return monpro(a, R2, n)

def from_montgomery(a_bar, n):
    """a = a_bar * R^{-1} mod n = MonPro(a_bar, 1)."""
    return monpro(a_bar, 1, n)

# --- RL binary exponentiation using MonPro ---

def montgomery_pow(base, exponent, modulus):
    if modulus == 1:
        return 0
    if exponent < 0:
        raise ValueError("Negative exponents not supported in this simple model.")

    base %= modulus
    if exponent == 0:
        return 1 % modulus

    # Precompute once (mirrors a hardware precompute register)
    R2 = precompute_R2_mod_n(modulus)

    # Enter Montgomery domain
    one_bar  = monpro(1,    R2, modulus)   # 1 * R mod n
    base_bar = monpro(base, R2, modulus)   # base * R mod n

    # RL binary exponentiation:
    # C := 1_bar; P := base_bar
    # for each bit (LSB->MSB): if bit=1: C=MonPro(C,P); P=MonPro(P,P)
    C = one_bar
    P = base_bar
    e = exponent
    while e:
        if e & 1:
            C = monpro(C, P, modulus)  # multiply when bit is 1
        P = monpro(P, P, modulus)      # square every iteration
        e >>= 1

    # Convert out of Montgomery domain
    return monpro(C, 1, modulus)






