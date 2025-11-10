A = 0x5b9e402b76181c9c95ce28ced7dde4c04d1e1f5773e9e67e4c907c8fa7c390cc
B = 0x1808a604ed7dedcf26e8e371a4e312a51fae740f749aaac0ac10c9cc3469d8d4
n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
np = 0x8833c3bb


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
for i in range(8):
    print("Index:", i)
    U = U + A_split[i]*B
    print("mul_1 U", hex(U))
    M = ((U % 2**32) * np) % 2**32
    print("mul_2 M", hex(M))
    U = U + M*n >> 32
    print("mul_3 U", hex(U))
print(hex(U))

assert 0xfc0007bb0f51e925d4a96ba63a5e5700ae1acffdd23e51bac4e76c07ba0a547c3cc08f0 == 0xfc0007bb0f51e925d4a96ba63a5e5700ae1acffdd23e51bac4e76c07ba0a547c3cc08f0

assert 0xb8a95750 == 0xb8a95750

assert 0x7e86c0ff525b3da206c3c5666aea8e726952735cd61cad5fc85116b0b94816ef == 0x7e86c0ff525b3da207c3c5666aea8e726952735cd61cad5fc85116b0b94816ef

0x7e86c0ff525b3da206c3c5666aea8e726952735cd61cad5fc85116b0b94816ef
0x7e86c0ff525b3da207c3c5666aea8e726952735cd61cad5fc85116b0b94816ef

0x73021d8f50cda383ef671b73de607030513909d7b4c462b22ad27b229dda10e2caee55b
0x73021d8f50cda383ef671b73ee607030513909d7b4c462b22ad27b229dda10e2caee55b
#  load 3
0xe596da79
0xe596da79

# assert 0x90ea838058752b5cf12e6e36054dd227b0fcdd5e06dcb1357e264834c766ba0f == 0x90ea838058752b5cf12e6e36064dd227b0fcdd5e06dcb1357e264834c766ba0f

# 0x90ea838058752b5cf12e6e36054dd227b0fcdd5e06dcb1357e264834c766ba0f
# 0x90ea838058752b5cf12e6e36064dd227b0fcdd5e06dcb1357e264834c766ba0f




















