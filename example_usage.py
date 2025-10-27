"""
Example usage of RSA encryption/decryption with Montgomery algorithm.
Demonstrates 256-bit RSA key operations.
"""

from rsa_montgomery import MontgomeryRSA, string_to_int, int_to_string


def main():
    print("RSA Encryption/Decryption with Montgomery Algorithm")
    print("=" * 55)
    
    # Example 256-bit RSA keys (generated properly for demonstration)
    # In practice, these would be generated using proper cryptographic methods
    # These are sample keys generated with reproducible seed for testing
    
    import random
    
    def is_prime(n, k=10):
        """Miller-Rabin primality test"""
        if n == 2 or n == 3:
            return True
        if n < 2 or n % 2 == 0:
            return False
        
        r = 0
        d = n - 1
        while d % 2 == 0:
            r += 1
            d //= 2
        
        for _ in range(k):
            a = random.randrange(2, n - 1)
            x = pow(a, d, n)
            if x == 1 or x == n - 1:
                continue
            for _ in range(r - 1):
                x = pow(x, 2, n)
                if x == n - 1:
                    break
            else:
                return False
        return True
    
    def generate_prime(bits):
        """Generate a prime number with specified bit length"""
        while True:
            candidate = random.getrandbits(bits)
            candidate |= (1 << bits - 1) | 1  # Set MSB and LSB
            if is_prime(candidate):
                return candidate
    
    # Use fixed seed for reproducible demonstration
    random.seed(42)
    p = generate_prime(128)
    q = generate_prime(128)
    n = p * q  # RSA modulus  
    e = 65537   # Public exponent
    
    # Calculate private exponent using extended Euclidean algorithm
    phi_n = (p - 1) * (q - 1)
    
    def extended_gcd(a, b):
        if a == 0:
            return b, 0, 1
        gcd, x1, y1 = extended_gcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y
    
    gcd, d, _ = extended_gcd(e, phi_n)
    d = d % phi_n
    if d < 0:
        d += phi_n
    
    print(f"RSA Key Parameters:")
    print(f"  n (modulus):     0x{n:064x}")
    print(f"  e (public exp):  {e}")
    print(f"  d (private exp): 0x{d:064x}")
    print(f"  Key size:        {n.bit_length()} bits")
    print()
    
    # Create RSA instance
    rsa = MontgomeryRSA(n, e, d)
    
    print("Montgomery Algorithm Parameters:")
    print(f"  R bit length: {rsa.r_bit_length}")
    print(f"  R:            0x{rsa.r:x}")
    print(f"  n':           0x{rsa.n_prime:x}")
    print()
    
    # Example 1: Encrypt/decrypt integer
    print("Example 1: Integer Encryption")
    print("-" * 30)
    
    message_int = 123456789
    print(f"Original message: {message_int}")
    
    ciphertext = rsa.encrypt(message_int)
    print(f"Encrypted:        {ciphertext}")
    print(f"Encrypted (hex):  0x{ciphertext:064x}")
    
    decrypted_int = rsa.decrypt(ciphertext)
    print(f"Decrypted:        {decrypted_int}")
    
    print(f"Success: {message_int == decrypted_int}")
    print()
    
    # Example 2: Encrypt/decrypt string
    print("Example 2: String Encryption")
    print("-" * 30)
    
    # Use a short string to ensure it fits in our key size
    original_text = "Secret!"
    message_int = string_to_int(original_text)
    
    print(f"Original text:    '{original_text}'")
    print(f"As integer:       {message_int}")
    print(f"Fits in key:      {message_int < n}")
    
    if message_int >= n:
        print("⚠ Message too large for key size, using shorter message")
        original_text = "Hi!"
        message_int = string_to_int(original_text)
        print(f"New text:         '{original_text}'")
        print(f"As integer:       {message_int}")
    
    ciphertext = rsa.encrypt(message_int)
    print(f"Encrypted:        {ciphertext}")
    
    decrypted_int = rsa.decrypt(ciphertext)
    decrypted_text = int_to_string(decrypted_int)
    
    print(f"Decrypted int:    {decrypted_int}")
    print(f"Decrypted text:   '{decrypted_text}'")
    print(f"Success:          {original_text == decrypted_text}")
    print()
    
    # Example 3: Performance comparison
    print("Example 3: Performance Comparison")
    print("-" * 35)
    
    import time
    
    test_message = 999999999
    iterations = 1000
    
    # Montgomery method
    start_time = time.time()
    for _ in range(iterations):
        result_mont = rsa._montgomery_exponentiation(test_message, e, n)
    mont_time = time.time() - start_time
    
    # Standard method
    start_time = time.time()
    for _ in range(iterations):
        result_std = pow(test_message, e, n)
    std_time = time.time() - start_time
    
    print(f"Montgomery method: {mont_time:.4f}s for {iterations} operations")
    print(f"Standard method:   {std_time:.4f}s for {iterations} operations")
    print(f"Results match:     {result_mont == result_std}")
    
    if mont_time < std_time:
        speedup = std_time / mont_time
        print(f"Montgomery is {speedup:.2f}x faster")
    else:
        slowdown = mont_time / std_time
        print(f"Montgomery is {slowdown:.2f}x slower")
    
    print()
    print("Note: For larger keys (1024+ bits), Montgomery algorithm")
    print("      typically shows more significant performance benefits.")


if __name__ == "__main__":
    main()