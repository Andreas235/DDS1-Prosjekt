s = 4 # Number of windows
r = 2
def quarternary_method(M, e, n):
    # Precomputed_table = [1, M, M**2, M**3]
    precomputed_table = [0 for i in range(4)]
    for i in range(0, 3):
        precomputed_table[i] = (M**i)
    precomputed_table[3] = precomputed_table[2] * M
    
    num_bits = 8
    F = []
    val = 0
    for i in reversed(range(num_bits)):
        if i & 1 == 1:
            if e >> i & 1:
                val = 2
        if i & 1 == 0:
            if e >> i & 1:
                val += 1
            F.append(val)
            val = 0
    F = list(reversed(F))
    
    C = M**F[s-1] % n
    mult_counter = 1
    for i in reversed(range(s-1)):
        C = C**2 % n
        C = C**2 % n
        mult_counter += 2
        if F[i] != 0:
            C = C * precomputed_table[F[i]] % n
            mult_counter += 1

    return C, mult_counter

C, mult_counter = quarternary_method(59, 5, 221)
print(C, mult_counter)

M, mult_counter = quarternary_method(C, 77, 221)
print(M, mult_counter)