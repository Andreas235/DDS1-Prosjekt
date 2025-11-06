"""
RSA Encryption/Decryption using Montgomery Algorithm
Supports 256-bit keys

This implementation uses Montgomery modular arithmetic for efficient
modular exponentiation in RSA operations.
"""

import math


class MontgomeryRSA:
    """RSA implementation using Montgomery algorithm for modular arithmetic."""
    
    def __init__(self, n, e, d=None):
        """
        Initialize RSA with given keys.
        
        Args:
            n (int): RSA modulus (256-bit)
            e (int): Public exponent
            d (int): Private exponent (optional, needed for decryption)
        """
        self.n = n
        self.e = e
        self.d = d
        
        # Calculate bit length and Montgomery parameters
        self.bit_length = n.bit_length()
        self.r_bit_length = self._find_r_bit_length()
        self.r = 1 << self.r_bit_length  # R = 2^r_bit_length
        self.r_mod_n = self.r % n
        self.n_prime = self._calculate_n_prime()
    
    def _find_r_bit_length(self):
        """Find appropriate R bit length (must be > bit length of n)."""
        return ((self.bit_length // 64) + 1) * 64  # Round up to multiple of 64
    
    def _calculate_n_prime(self):
        """Calculate n' such that n * n' ≡ -1 (mod R)."""
        # Extended Euclidean algorithm to find modular inverse
        def extended_gcd(a, b):
            if a == 0:
                return b, 0, 1
            gcd, x1, y1 = extended_gcd(b % a, a)
            x = y1 - (b // a) * x1
            y = x1
            return gcd, x, y
        
        # We need n * n_prime ≡ -1 (mod R)
        # So n_prime ≡ -n^(-1) (mod R)
        gcd, inv_n, _ = extended_gcd(self.n, self.r)
        if gcd != 1:
            raise ValueError("n and R must be coprime")
        
        n_prime = (-inv_n) % self.r
        return n_prime
    
    def _montgomery_reduction(self, t):
        """
        Montgomery reduction: compute t * R^(-1) mod n.
        
        Args:
            t (int): Input value (must be < n * R)
            
        Returns:
            int: t * R^(-1) mod n
        """
        m = ((t % self.r) * self.n_prime) % self.r
        u = (t + m * self.n) // self.r
        
        if u >= self.n:
            return u - self.n
        return u
    
    def _to_montgomery_form(self, a):
        """Convert a to Montgomery form: a * R mod n."""
        return (a * self.r) % self.n
    
    def _from_montgomery_form(self, a_mont):
        """Convert from Montgomery form to normal form."""
        return self._montgomery_reduction(a_mont)
    
    def _montgomery_multiply(self, a_mont, b_mont):
        """
        Montgomery multiplication: compute (a * b * R^(-1)) mod n.
        Both inputs must be in Montgomery form.
        """
        return self._montgomery_reduction(a_mont * b_mont)
    
    def _montgomery_exponentiation(self, base, exponent, modulus):
        """
        Modular exponentiation using Montgomery algorithm.
        
        Args:
            base (int): Base value
            exponent (int): Exponent
            modulus (int): Modulus (should be self.n)
            
        Returns:
            int: base^exponent mod modulus
        """
        if modulus != self.n:
            # Fall back to standard modular exponentiation for different modulus
            return pow(base, exponent, modulus)
        
        # Convert base to Montgomery form
        base_mont = self._to_montgomery_form(base % self.n)
        result_mont = self._to_montgomery_form(1)  # 1 in Montgomery form
        
        # Binary exponentiation in Montgomery domain
        exp_bits = bin(exponent)[2:]  # Remove '0b' prefix
        
        for bit in exp_bits:
            result_mont = self._montgomery_multiply(result_mont, result_mont)  # Square
            if bit == '1':
                result_mont = self._montgomery_multiply(result_mont, base_mont)  # Multiply
        
        # Convert result back to normal form
        return self._from_montgomery_form(result_mont)
    
    def encrypt(self, message):
        """
        Encrypt a message using RSA.
        
        Args:
            message (int): Message to encrypt (must be < n)
            
        Returns:
            int: Encrypted message (ciphertext)
        """
        if message >= self.n:
            raise ValueError("Message must be smaller than modulus n")
        
        return self._montgomery_exponentiation(message, self.e, self.n)
    
    def decrypt(self, ciphertext):
        """
        Decrypt a ciphertext using RSA.
        
        Args:
            ciphertext (int): Ciphertext to decrypt
            
        Returns:
            int: Decrypted message (plaintext)
        """
        if self.d is None:
            raise ValueError("Private key (d) not provided for decryption")
        
        if ciphertext >= self.n:
            raise ValueError("Ciphertext must be smaller than modulus n")
        
        return self._montgomery_exponentiation(ciphertext, self.d, self.n)


def bytes_to_int(byte_data):
    """Convert bytes to integer."""
    return int.from_bytes(byte_data, byteorder='big')


def int_to_bytes(integer, byte_length):
    """Convert integer to bytes with specified length."""
    return integer.to_bytes(byte_length, byteorder='big')


def string_to_int(text):
    """Convert string to integer for encryption."""
    return bytes_to_int(text.encode('utf-8'))


def int_to_string(integer):
    """Convert integer back to string after decryption."""
    # Calculate byte length needed
    byte_length = (integer.bit_length() + 7) // 8
    if byte_length == 0:
        byte_length = 1
    return int_to_bytes(integer, byte_length).decode('utf-8')