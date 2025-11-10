from typing import List, Tuple

def schedule_lsb_sliding_packed(exp: int, w: int = 4) -> List[Tuple[int,int]]:
    """LSB-first (right-to-left) schedule of (u, L). Multiply by A^u then L squarings. Zeros packed up to w."""
    if exp <= 0:
        return []
    bits = [(exp >> i) & 1 for i in range(exp.bit_length())]  # LSB->MSB
    n, i, out = len(bits), 0, []
    while i < n:
        if bits[i] == 0:
            run = 0
            while i + run < n and bits[i + run] == 0:
                run += 1
            k = run
            while k > 0:
                L = min(w, k)
                out.append((0, L))
                k -= L
            i += run
        else:
            L = min(w, n - i)
            while L > 1 and bits[i + L - 1] == 0:
                L -= 1
            u = 0
            for j in range(L):
                u |= (bits[i + j] << j)  # LSB-first value
            if (u & 1) == 0 or u > 15:
                raise ValueError(f"Invalid window u={u} at bit {i}")
            out.append((u, L))
            i += L
    return out

def verify_lsb(entries: List[Tuple[int,int]]) -> int:
    E = 0
    for (u,L) in entries:       # multiply, then L squarings
        E = (E + u) << L
    return E

def verify_msb(entries: List[Tuple[int,int]]) -> int:
    E = 0
    for (u,L) in entries:       # L squarings, then multiply
        E = (E << L) + u
    return E

def pack_three_regs(entries_msb: List[Tuple[int,int]]):
    """
    Pack MSB-first entries into three 256b regs for your controller:
      reg0[255:249] = length (7b, MSB first)
      reg0[248:3]   = first 246 payload bits (MSB-first)
      reg0[2:0]     = 000 (ignored)
      reg1[255:0]   = next 256 payload bits (MSB-first)
      reg2[255:0]   = next 256 payload bits (MSB-first)
    Returns (reg0_hex, reg1_hex, reg2_hex, length).
    """
    # encode each entry as 6 bits MSB-first: [u3 u2 u1 u0][ss1 ss0], where ss = L-1
    payload_bits = []
    for (u,L) in entries_msb:
        ss = (L - 1) & 0b11
        code = ((u & 0xF) << 2) | ss
        payload_bits.extend([(code >> k) & 1 for k in range(5, -1, -1)])  # MSB->LSB

    length = len(entries_msb)
    if length >= (1 << 7):
        raise ValueError("Entry count won't fit in 7 bits")

    # Build reg0
    reg0 = [ (length >> (6 - i)) & 1 for i in range(7) ]  # len MSB-first
    take0 = min(246, len(payload_bits))
    reg0 += payload_bits[:take0]
    reg0 += [0,0,0]  # ignored padding
    if len(reg0) < 256:
        reg0 += [0] * (256 - len(reg0))
    elif len(reg0) > 256:
        raise RuntimeError("reg0 overfilled (shouldn't happen)")

    # Build reg1
    rem = payload_bits[take0:]
    take1 = min(256, len(rem))
    reg1 = rem[:take1]
    if len(reg1) < 256:
        reg1 += [0] * (256 - len(reg1))
    rem = rem[take1:]

    # Build reg2
    take2 = min(256, len(rem))
    reg2 = rem[:take2]
    if len(reg2) < 256:
        reg2 += [0] * (256 - len(reg2))
    rem = rem[take2:]

    if rem:
        raise ValueError("Payload exceeds three 256-bit registers—add a 4th if needed")

    def bits_to_hex(msb_bits):
        v = 0
        for b in msb_bits:
            v = (v << 1) | b
        return f"0x{v:064x}"

    return bits_to_hex(reg0), bits_to_hex(reg1), bits_to_hex(reg2), length

# ---- Usage for your key d ----
# 1) Build LSB-first entries (multiply-then-square)
# 2) Reverse for hardware (MSB-first, square-then-multiply)
key_d = key_d = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9
d = int(key_d)
entries_lsb = schedule_lsb_sliding_packed(d, w=4)
#assert verify_lsb(entries_lsb) == d
entries_msb = list(reversed(entries_lsb))
#assert verify_msb(entries_msb) == d

reg0_hex, reg1_hex, reg2_hex, length = pack_three_regs(entries_msb)
print("reg0 =", reg0_hex)
print("reg1 =", reg1_hex)
print("reg2 =", reg2_hex)
print("len  =", length)

