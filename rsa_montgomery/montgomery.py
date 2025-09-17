
#BINARY MONTGOMERY

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




