n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
np = 0x8833c3bb
# Test 1 - Fail
A = 0x7b2c2cff3781db07b42ff01e242a6cfe7ef25a57c9491d84cb72a139c3897b63
B = 0xf89aec4f5d4fab3f990d9124b40120839f8e068c36f94daf6cbd33e0955a2211
# Test 2 - Pass
A = 0x150d69cbcd04a2eba06ed0efd0183603ad5662ebf4dbc96f87a03d93643c35f0
B = 0x038d882148c1d21a0983141322c900c0a702f60165aac0efdb88016de7ec9e05

def very_high_level_monpro(a, b, n):
    return a * b * pow(1 << 256, -1, n) % n

R = very_high_level_monpro(A, B, n)

print("A:", hex(A))
print("B:", hex(B))
print("R:", hex(R))


def int_to_words(x, w):
    """Split integer into list of w-bit words, LSB first."""
    words = []
    mask = (1 << w) - 1
    while x:
        words.append(x & mask)
        x >>= w
    return words or [0]

A_split = int_to_words(A, 32)

U = 0
M = 0
for i in range(1):
    print("Index:", i)
    P = A_split[i]*B
    print("mul_1 P", hex(P))
    U = U + P
    print("mul_1 U", hex(U))
    M = ((U % 2**32) * np) % 2**32
    print("mul_2 M", hex(M))
    P = M*n
    print("mul_2 P", hex(P))
    U = U + P >> 32
    print("mul_3 U", hex(U))
if U >= n:
    U = U - n
monpro_radix = U
print("U:", hex(U))

















