# HIGH-RADIX MONTGOMERY WITH VLNW
import random

# -----------------------------
# PARAMETERS
# -----------------------------
R_BITS = 256          # modulus length in bits
WORD_BITS = 32        # high-radix word size
R = 1 << R_BITS

# Global multiplication counter
mul_count = 0

# -----------------------------
# Helpers
# -----------------------------
def int_to_words(x, w=WORD_BITS):
    """Split integer into list of w-bit words, LSB first."""
    words = []
    mask = (1 << w) - 1
    while x:
        words.append(x & mask)
        x >>= w
    return words or [0]

def words_to_int(words, w=WORD_BITS):
    """Combine list of w-bit words into integer."""
    x = 0
    for i in reversed(range(len(words))):
        x = (x << w) | words[i]
    return x

def modinv(a, m):
    """Modular inverse using extended Euclidean algorithm."""
    g, x, y = extended_gcd(a, m)
    if g != 1:
        raise ValueError("No modular inverse")
    return x % m

def extended_gcd(a, b):
    """Extended GCD algorithm."""
    if b == 0:
        return a, 1, 0
    g, y, x = extended_gcd(b, a % b)
    y -= (a // b) * x
    return g, x, y

# -----------------------------
# High-Radix Montgomery Multiplication
# -----------------------------
def monpro_hr(a_bar, b_bar, n, w=WORD_BITS):
    """
    High-Radix Montgomery multiplication:
    Computes a_bar * b_bar * R^-1 mod n
    """
    global mul_count
    mul_count += 1

    # Precompute n0_inv = -n0^-1 mod 2^w
    n0 = n & ((1 << w) - 1)
    n0_inv = (-modinv(n0, 1 << w)) & ((1 << w) - 1)
    A = int_to_words(a_bar, w)
    B = int_to_words(b_bar, w)
    s = len(A)
    u = 0

    for i in range(s):
        Ai = A[i]
        # Multiply-add step
        u += Ai * b_bar
        u0 = u & ((1 << w) - 1)
        m = (u0 * n0_inv) & ((1 << w) - 1)
        u += m * n
        u >>= w

    if u >= n:
        u -= n
    return u

# -----------------------------
# Conversions to/from Montgomery domain
# -----------------------------
def to_montgomery(a, n):
    return (a << R_BITS) % n

def from_montgomery(a_bar, n):
    return monpro_hr(a_bar, 1, n)  # multiply by 1 in HR-MonPro

# -----------------------------
# VLNW schedule generator
# -----------------------------
def vlnw_schedule(exponent: int, d):
    d = 4
    e_bits = bin(exponent)[2:][::-1]  # LSB first
    schedule = []
    i = 0
    while i < len(e_bits):
        if e_bits[i] == '0':
            schedule.append((0, 1))
            i += 1
        else:
            win_len = min(d, len(e_bits) - i)
            val = 0
            for j in range(win_len):
                val |= (int(e_bits[i + j]) << j)
            schedule.append((val, win_len))
            i += win_len
    # print(schedule)
    # print(len(schedule))

    return schedule

# -----------------------------
# Precompute odd powers of base
# -----------------------------
def precompute_base_powers(base_bar, modulus, d):
    max_w = (1 << d) - 1
    powers = {1: base_bar}
    M2 = monpro_hr(base_bar, base_bar, modulus)
    for w in range(3, max_w + 1, 2):
        powers[w] = monpro_hr(powers[w - 2], M2, modulus)
    return powers

def very_high_level_monpro(a, b, n):
    return a * b * pow(1 << R_BITS, -1, n) % n
# -----------------------------
# VLNW Montgomery exponentiation (High-Radix)
# -----------------------------
def montgomery_pow_vlnw_hr(msgin_data, exponent, modulus, d):
    if modulus == 1:
        return 0
    if exponent == 0:
        return 1 % modulus

    msgin_data_bar = to_montgomery(msgin_data, modulus)

    powers = precompute_base_powers(msgin_data_bar, modulus, d)
    # print("Message:", hex(msgin_data))
    # print("Message_bar:",hex(msgin_data_bar))
    # print(len(powers), "precomputed powers")
    # print("Precomputed powers:")
    # for w, p in powers.items():
    #     print(f"  M^{w} mod n: {hex(p)}")
    schedule = vlnw_schedule(exponent, d)

    # Initialize accumulator to the most significant non-zero window (step 3)
    windows = list(reversed(schedule))
    # Find first non-zero window (should be windows[0], but guard just in case)
    start_idx = 0
    while start_idx < len(windows) and windows[start_idx][0] == 0:
        start_idx += 1
    if start_idx == len(windows):
        return 1 % modulus  # exponent was zero (already handled), safe guard
    
    acc = powers[windows[start_idx][0]]  # C := M^{F_{k-1}} in Montgomery domain
    start_idx += 1
    # print(hex(acc))
    # Process remaining windows (steps 4a, 4b)
    for win_val, win_len in windows[start_idx:]:
        for _ in range(win_len):
            acc = monpro_hr(acc, acc, modulus)  # square L(Fi) times
        if win_val != 0:
            # print("acc prev",hex(acc))
            # print("mult", hex(powers[win_val]))
            # print("Very high level monpro:\nacc", hex(very_high_level_monpro(acc, powers[win_val], modulus)))
            acc = monpro_hr(acc, powers[win_val], modulus)  # multiply by M^{Fi}
            # print("acc", hex(acc), '\n')
            

    return from_montgomery(acc, modulus)

# -----------------------------
# -----------------------------
# TEST
# -----------------------------
if __name__ == "__main__":
    # Example 256-bit RSA modulus and exponents
    key_n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
    key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
    key_e = 0x0000000000000000000000000000000000000000000000000000000000010001

    test_key = random.getrandbits(256)
    # Random message
    M = random.getrandbits(255)
    # M = 0x47D69AAD3C674409759981524CE494FD331DBE831A4970E6D6AB58052FFF24D0

    print("Original   M:", hex(M))
    # print("Testing VLNW high-radix Montgomery (w={} bits)...".format(WORD_BITS))

    # Encryption
    mul_count = 0
    C = montgomery_pow_vlnw_hr(M, key_e, key_n, 4)
    print("Ciphertext C:", hex(C))
    # print("Multiplications:", mul_count)

    # Decryption
    mul_count = 0
    M_dec = montgomery_pow_vlnw_hr(C, key_d, key_n, 4)
    print("Decrypted  M:", hex(M_dec))
    # print("Multiplications:", mul_count)

    assert M_dec == M, "High-radix VLNW failed!"
    print("High-radix VLNW test passed!")

# def precompute_R2_modn__and_n0_prime(key_n):
#   R = 1 << 256
#   w = 32
#   n0 = key_n & ((1 << w) - 1)
#   n0_inv = (-modinv(n0, 1 << w)) & ((1 << w) - 1)
#   return R**2 % key_n, n0_inv

# # constants:
# n_prime = 0x8833c3bb
# n = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
# M = 0x47D69AAD3C674409759981524CE494FD331DBE831A4970E6D6AB58052FFF24D0
# D = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
# R2modn= R**2 % n
# assert 0x56ddf8b43061ad3dbcd1757244d1a19e2e8c849dde4817e55bb29d1c20c06364 == 0x56DDF8B43061AD3DBCD1757244D1A19E2E8C849DDE4817E55BB29D1C20C06364

# # Values for testing monpro
# A_hex = 0x69ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567
# B_hex = 0x6EDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210
# result_hex = 0x328A777F8CDFBE115693E4C5B3C3487EDC08CAD3799F63BBA4C6F836A2E4F601
# # In decimal:
# A = 26221972580484093740929283297649652438104371637947502249586941047847278433329
# B = 36110714871347089791863259127184075564532056788360915503311257584139326612342
# result = 22860292070666994401101343068437819156805801020233103670795281969203858699777

# print(monpro_hr(A,B,n))


# # For testing to, from montgomery and monpro

# abar = to_montgomery(int(A), int(n))
# bbar = to_montgomery(int(B), int(n))

# # print(abar, bbar)

# pbar = monpro_hr(abar, bbar, int(n))

# # print(pbar)
# # Example values for testing monpro
# A = 0x39F91C4BC9714E29EE7140682C2F5EFA99801EA45044AA7C4F8A9AE1E0355431
# B = 0x4FD5F0B910B12F3310DC4044C56C4A36693F0E82746C497BC74178EB6E326376
# p_fin = from_montgomery(pbar, int(n))

# check = int(A) * int(B) % int(n)
# # print(p_fin)
# # print(check)

# print(monpro_hr(0x0f793fa1b23135af844376afa0254206772157962c7cbe9ce321a534dc7d634b, 0x26c5eb1b633656a4a8935dbfec7809d5f0ab227524f0ed33c2721ef49f7468c1, 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d))


# Help from chatGPT:

# Name: GitHub Copilot

# Yes. Here’s a concrete integration plan and the patches to make your VLNW exponentiation core work end‑to‑end with rsa_soc, rsa_core and the existing testbench, plus SW control via the notebook. It keeps your INIT to the precomputed power (no 1̄ init needed in hardware) by encoding that into the first micro‑op (nsq=0, multiply first window).

# What I’m changing

# Add registers for R^2 mod n, n_prime, and an optional prepacked schedule to rsa_regio.
# Wire these to rsa_core and exponentiation.
# Let exponentiation auto-generate the schedule from key if sched_hi/lo are zero (so the premade testbench “just works”).
# Keep nsq=2-bit micro-ops but allow long runs by splitting into filler ops (nsq<=3, tidx=0 => “square only”).
# In the testbench, compute r2_mod_n and n_prime from key_n and pass to rsa_core.
# In the notebook, compute and write r2_mod_n, n_prime, and (optionally) prepacked schedule.
# Patches

# Expose new registers and buses from rsa_regio (increase register space)
# Wire new regs in rsa_accelerator
# Pass-through in rsa_core
# Auto-generate schedule if none provided (exponentiation.vhd)
# Make the premade testbench pass the new rsa_core ports (and compute r2/n’)
# Notebook: write constants and (optionally) schedule to the HW
# Build and run

# Vivado sim: re-run with the updated files; the premade testbench should pass (schedule auto-generation runs inside exponentiation; TB computes r2/n’).
# PYNQ: in the notebook, set C_ENCR_ALGORITHM = C_ENCR_ALGORITHM_RSA, call write_consts_and_schedule before DMA. Test 4 should meet <24 ms on Zynq-7000 at 100–150 MHz if the monpro clock is fast enough.
# Performance tips to hit <24 ms for test 4

# Synthesize monpro at 150–200 MHz if possible; set clock constraints and enable DSP inference (your 16x16 split already maps cleanly to DSP48).
# Keep WINDOW_D=4 (you already do). The d=4 precompute table is 8 odd powers; negligible area.
# Ensure no resource sharing on DSPs in synthesis (set resource_sharing off for speed).
# Enable “Performance_Explore” strategy in Vivado (synth + opt + place).
# In the notebook, avoid extra Python MMIO per block; write constants once, then stream blocks via DMA.
# If you want, I can also generate a tiny Python script to sanity-check that SW and HW produce identical schedules for a few random exponents, or adapt the entry_counter/vlnw_controller path to drive your monpro directly.

