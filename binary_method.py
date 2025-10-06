def binary_method(M, e, n):
    mult_counter = 0
    num_bits = 8
    if e >> num_bits-1 & 1: # Checking leftmost bit
        C = M
    else:
        C = 1
    for i in reversed(range(num_bits)):
        C *= C % n
        mult_counter += 1
        if e >> i & 1:
            C = C*M % n
            mult_counter += 1
    return C, mult_counter

C, mult_counter = binary_method(59, 5, 221)
print(C, mult_counter)

M, mult_counter = binary_method(C, 77, 221)
print(M, mult_counter)