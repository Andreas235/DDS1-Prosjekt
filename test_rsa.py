"""
Test cases for RSA Montgomery implementation.
Tests encryption/decryption with 256-bit keys.
"""

from rsa_montgomery import MontgomeryRSA, string_to_int, int_to_string, bytes_to_int, int_to_bytes


def test_key_generation():
    """Test with sample 256-bit RSA keys."""
    # Properly generated 256-bit RSA keys (using reproducible seed)
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
    
    # Use fixed seed for reproducible tests
    random.seed(42)
    p = generate_prime(128)
    q = generate_prime(128)
    
    n = p * q  # 256-bit modulus
    phi_n = (p - 1) * (q - 1)
    e = 65537  # Common public exponent
    
    # Calculate private exponent d
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
    
    print(f"Test Keys Generated:")
    print(f"p = 0x{p:032x}")
    print(f"q = 0x{q:032x}")
    print(f"n = 0x{n:064x}")
    print(f"e = {e}")
    print(f"d = 0x{d:064x}")
    print(f"n bit length: {n.bit_length()} bits")
    print()
    
    return n, e, d


def test_montgomery_operations():
    """Test Montgomery arithmetic operations."""
    print("Testing Montgomery operations...")
    
    n, e, d = test_key_generation()
    rsa = MontgomeryRSA(n, e, d)
    
    # Test Montgomery form conversion
    test_val = 12345
    mont_form = rsa._to_montgomery_form(test_val)
    back_to_normal = rsa._from_montgomery_form(mont_form)
    
    print(f"Original value: {test_val}")
    print(f"Montgomery form: {mont_form}")
    print(f"Back to normal: {back_to_normal}")
    assert test_val == back_to_normal, "Montgomery form conversion failed"
    print("✓ Montgomery form conversion test passed")
    
    # Test Montgomery multiplication
    a, b = 1234, 5678
    a_mont = rsa._to_montgomery_form(a)
    b_mont = rsa._to_montgomery_form(b)
    
    # Montgomery multiplication
    result_mont = rsa._montgomery_multiply(a_mont, b_mont)
    result = rsa._from_montgomery_form(result_mont)
    expected = (a * b) % n
    
    print(f"Montgomery multiplication: {a} * {b} mod {n}")
    print(f"Result: {result}")
    print(f"Expected: {expected}")
    assert result == expected, "Montgomery multiplication failed"
    print("✓ Montgomery multiplication test passed")
    print()


def test_encryption_decryption():
    """Test RSA encryption and decryption."""
    print("Testing RSA encryption/decryption...")
    
    n, e, d = test_key_generation()
    rsa = MontgomeryRSA(n, e, d)
    
    # Test with a simple integer message
    message = 123456789
    print(f"Original message: {message}")
    
    # Encrypt
    ciphertext = rsa.encrypt(message)
    print(f"Encrypted: {ciphertext}")
    
    # Decrypt
    decrypted = rsa.decrypt(ciphertext)
    print(f"Decrypted: {decrypted}")
    
    assert message == decrypted, f"Encryption/Decryption failed: {message} != {decrypted}"
    print("✓ Integer encryption/decryption test passed")
    print()


def test_string_encryption():
    """Test RSA encryption with string messages."""
    print("Testing string encryption/decryption...")
    
    n, e, d = test_key_generation()
    rsa = MontgomeryRSA(n, e, d)
    
    # Test with string (need to ensure it's smaller than n)
    original_string = "Hello RSA!"
    message_int = string_to_int(original_string)
    
    print(f"Original string: '{original_string}'")
    print(f"As integer: {message_int}")
    
    if message_int >= n:
        print("⚠ Warning: String too large for this key size, using smaller message")
        original_string = "Hi!"
        message_int = string_to_int(original_string)
        print(f"New string: '{original_string}'")
        print(f"As integer: {message_int}")
    
    # Encrypt
    ciphertext = rsa.encrypt(message_int)
    print(f"Encrypted: {ciphertext}")
    
    # Decrypt
    decrypted_int = rsa.decrypt(ciphertext)
    decrypted_string = int_to_string(decrypted_int)
    
    print(f"Decrypted as int: {decrypted_int}")
    print(f"Decrypted as string: '{decrypted_string}'")
    
    assert original_string == decrypted_string, f"String encryption failed: '{original_string}' != '{decrypted_string}'"
    print("✓ String encryption/decryption test passed")
    print()


def test_edge_cases():
    """Test edge cases."""
    print("Testing edge cases...")
    
    n, e, d = test_key_generation()
    rsa = MontgomeryRSA(n, e, d)
    
    # Test with message = 1
    message = 1
    ciphertext = rsa.encrypt(message)
    decrypted = rsa.decrypt(ciphertext)
    assert message == decrypted, "Failed for message = 1"
    print("✓ Message = 1 test passed")
    
    # Test with message = 0
    message = 0
    ciphertext = rsa.encrypt(message)
    decrypted = rsa.decrypt(ciphertext)
    assert message == decrypted, "Failed for message = 0"
    print("✓ Message = 0 test passed")
    
    # Test with largest possible message (n-1)
    message = n - 1
    ciphertext = rsa.encrypt(message)
    decrypted = rsa.decrypt(ciphertext)
    assert message == decrypted, "Failed for message = n-1"
    print("✓ Message = n-1 test passed")
    print()


def test_montgomery_vs_standard():
    """Compare Montgomery exponentiation with standard pow()."""
    print("Comparing Montgomery vs standard exponentiation...")
    
    n, e, d = test_key_generation()
    rsa = MontgomeryRSA(n, e, d)
    
    message = 42424242
    
    # Montgomery method
    mont_result = rsa._montgomery_exponentiation(message, e, n)
    
    # Standard method
    std_result = pow(message, e, n)
    
    print(f"Montgomery result: {mont_result}")
    print(f"Standard result:   {std_result}")
    
    assert mont_result == std_result, "Montgomery exponentiation doesn't match standard"
    print("✓ Montgomery exponentiation matches standard implementation")
    print()


if __name__ == "__main__":
    print("Running RSA Montgomery Algorithm Tests")
    print("=" * 50)
    
    try:
        test_montgomery_operations()
        test_encryption_decryption()
        test_string_encryption()
        test_edge_cases()
        test_montgomery_vs_standard()
        
        print("🎉 All tests passed!")
        
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        raise