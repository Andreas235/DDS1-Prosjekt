def vlnw_schedule(exponent: int, window_size: int = 4):
    """
    Generate the VLNW execution schedule for a given exponent.

    Parameters:
        exponent (int): The RSA exponent (e or d)
        window_size (int): Max length of a nonzero window (default 4)

    Returns:
        odd_values (list): Odd indices used for precomputation
        schedule (list of dicts): Each dict has 'num_squares' and 'multiply' keys
    """
    # Convert exponent to binary string, LSB first
    bin_exp = bin(exponent)[2:][::-1]

    i = 0
    n = len(bin_exp)
    windows = []

    while i < n:
        if bin_exp[i] == '0':
            # zero window of length 1
            windows.append((0, 1))
            i += 1
        else:
            # nonzero window, up to window_size bits
            w_len = min(window_size, n - i)
            # collect bits for the window
            window_bits = bin_exp[i:i + w_len]
            # ensure LSB=1 (nonzero)
            window_value = int(window_bits[::-1], 2)
            windows.append((window_value, w_len))
            i += w_len

    # build execution schedule
    schedule = []
    for w_val, w_len in windows:
        step = {
            'num_squares': w_len,
            'multiply': w_val if w_val != 0 else None
        }
        schedule.append(step)

    # Precompute odd powers needed
    odd_values = [1,3,5,7,9,11,13,15]

    return odd_values, schedule


def verify_vlnw(exponent: int, schedule: list):
    """
    Verify that the VLNW schedule correctly represents the exponent.
    Returns the reconstructed exponent and a summary of operations.
    """
    reconstructed = 0
    total_squares = 0
    total_multiplies = 0
    shift = 0

    for step in schedule:

        reconstructed += (step['multiply'] if step['multiply'] is not None else 0) << shift
        shift += step['num_squares']
        total_squares += step['num_squares']
        if step['multiply'] is not None:
            total_multiplies += 1
        print(step)
        print(reconstructed)

    print(reconstructed)
    is_correct = reconstructed == exponent
    summary = {
        'is_correct': is_correct,
        'total_squares': total_squares,
        'total_multiplies': total_multiplies
    }
    return reconstructed, summary


# --- TEST EXAMPLE ---
if __name__ == "__main__":
    import random

    # Random 256-bit exponent
    # e = random.getrandbits(256)
    e = 0x1234
    print('E:', e)

    odd_vals, sched = vlnw_schedule(e, window_size=4)
    reconstructed, summary = verify_vlnw(e, sched)

    # print("Exponent (LSB first):", bin(e)[2:][::-1])
    # print("Odd values needed:", odd_vals)
    # print("Execution schedule:")
    # for s in sched:
        # print(s)

    # print("\nVerification:")
    # print("Reconstructed exponent correct:", summary['is_correct'])
    # print("Total squarings:", summary['total_squares'])
    # print("Total multiplications:", summary['total_multiplies'])
