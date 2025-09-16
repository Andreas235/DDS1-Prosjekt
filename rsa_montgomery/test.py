from montgomery import montgomery_pow

# Tiny RSA toy example (from your slides, not 256 bits yet)
n = 119
e = 5
d = 77
M = 19

# Encrypt
C = montgomery_pow(M, e, n)
print("Ciphertext =", C)

# Decrypt
M2 = montgomery_pow(C, d, n)
print("Decrypted =", M2)
print("Correct:", M == M2)


# Example with a 256-bit modulus
n = (1 << 255) | 1        # 256-bit odd modulus
e = 65537                 # common RSA exponent
M = 123456789             # message smaller than n

C = montgomery_pow(M, e, n)
print("\n256-bit example:")
print("Ciphertext =", C)

# (we don't have d here, but this shows encryption works)