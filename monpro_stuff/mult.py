Ai = 0x892f3eac
B = 0x99925173AD65686715385EA800CD28120288FC70A9BC98DD4C90D676F8FF768D
U = 0x8808a604ed7dedcf26e8e371a4e312a51fae740f749aaac0ac10c9cc3469d8d452893f4d

golden_prod = Ai*B
golden_res = Ai*B + U

def int_to_words(x, w):
    """Split integer into list of w-bit words, LSB first."""
    words = []
    mask = (1 << w) - 1
    while x:
        words.append(x & mask)
        x >>= w
    return words or [0]

B_split = int_to_words(B, 32)
U_split = int_to_words(U, 36)

prod = 0
for i in range(8):
    prod += (Ai * B_split[i]) << 32*i
assert prod == golden_prod, f"prod mismatch: expected:\n{golden_prod:#x}, got:\n{prod:#x}"

res = 0
i = 0
res0 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 1
res1 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
for i in range(8):
    res += ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
assert res == golden_res, f"res mismatch: expected:\n{golden_res:#x}, got:\n{res:#x}"

print(220/32)

i = 0
res0 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 1
res1 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 2
res2 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 3
res3 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 4
res4 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 5
res5 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 6
res6 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))
i = 7
res7 = ((Ai * B_split[i]) << (32*i)) + (U_split[i] << (36*i))

parts = [res0, res1, res2, res3, res4, res5, res6, res7]
for limb in parts:
    print(hex(limb))

