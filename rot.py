# The Sliding Window Method
# Input: M ; e; n. Output: C = Me (mod n).
# 1. Compute and store Mw
# (mod n) for all w = 3; 5; 7;:::; 2
# d  1.
# 2. Decompose e into zero and nonzero windows Fi of length L(Fi)
# for i = 0; 1; 2;:::;p  1.
# 3. C := MFk1 (mod n)
# 4. for i = p  2 downto 0
# 4a. C := C2L(Fi ) (mod n)
# 4b. if Fi 6= 0 then C := C * MFi (mod n)
# 5. return C


bit = (e >> i) & 1
        print(f"Bit {i}: {bit}")

# This scans the bits of e
def bit_scan(e):
    num_bits = e.bit_length()
    for i in reversed(range(num_bits)):
        print(e >> i & 1)
        
bit_scan(0b1010101010)