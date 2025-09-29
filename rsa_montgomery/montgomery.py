# montgomery_fixed.py — binary Montgomery (k = 256) with to/from via monpro

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
    Works for either:
      - a,b already in Montgomery domain, or
      - one 'normal' and one special constant like R^2 mod n (see to_montgomery).
    """
    T = a * b
    return montgomery_redc(T, n)

def precompute_R2_mod_n(n):
    """
    Compute R^2 mod n once and reuse it (hardware: store in a register).
    With fixed R=2^256, this is cheap.
    """
    r_mod = R % n
    return (r_mod * r_mod) % n

# --- Conversions implemented via MonPro ---

def to_montgomery(a, n):
    """
    a_bar = a * R mod n = MonPro(a, R^2 mod n).
    (Because MonPro multiplies by R^{-1}, feeding R^2 yields a*R.)
    """
    R2 = precompute_R2_mod_n(n)
    return monpro(a, R2, n)

def from_montgomery(a_bar, n):
    """
    a = a_bar * R^{-1} mod n = MonPro(a_bar, 1).
    """
    return monpro(a_bar, 1, n)

# --- Modular exponentiation using MonPro ---

def montgomery_pow(base, exponent, modulus):
    if modulus == 1:
        return 0
    if exponent < 0:
        raise ValueError("Negative exponents not supported in this simple model.")

    base %= modulus
    if exponent == 0:
        return 1 % modulus

    # Precompute and reuse R^2 mod n once (exactly what you'd do in hardware).
    R2 = precompute_R2_mod_n(modulus)

    # Domain conversion via MonPro
    one_bar  = monpro(1,    R2, modulus)   # = 1*R mod n
    base_bar = monpro(base, R2, modulus)   # = base*R mod n

    acc = one_bar
    for bit in reversed(range(exponent.bit_length())):
        acc = monpro(acc, acc, modulus)          # square (Montgomery domain)
        if (exponent >> bit) & 1:
            acc = monpro(acc, base_bar, modulus) # multiply (Montgomery domain)

    return from_montgomery(acc, modulus)





