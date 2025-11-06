# DDS1-Prosjekt

## RSA Encryption/Decryption with Montgomery Algorithm

This repository implements RSA encryption and decryption using the Montgomery algorithm for efficient modular arithmetic operations. The implementation supports 256-bit RSA keys as specified.

### Features

- **RSA Encryption/Decryption**: Complete implementation of RSA public-key cryptography
- **Montgomery Algorithm**: Efficient modular arithmetic using Montgomery reduction
- **256-bit Key Support**: Designed to work with 256-bit RSA keys
- **Text and Binary Support**: Can encrypt both integer messages and text strings

### Files

- `rsa_montgomery.py` - Main RSA implementation with Montgomery algorithm
- `test_rsa.py` - Comprehensive test suite
- `example_usage.py` - Example usage and demonstrations
- `README.md` - This documentation

### Usage

#### Basic Example

```python
from rsa_montgomery import MontgomeryRSA, string_to_int, int_to_string

# Initialize with RSA parameters (n, e, d)
# Keys must be properly generated RSA parameters
rsa = MontgomeryRSA(n, e, d)

# Encrypt a message
message = 123456789
ciphertext = rsa.encrypt(message)

# Decrypt the ciphertext
plaintext = rsa.decrypt(ciphertext)

# For text messages
text = "Hello World!"
message_int = string_to_int(text)
encrypted = rsa.encrypt(message_int)
decrypted_int = rsa.decrypt(encrypted)
decrypted_text = int_to_string(decrypted_int)
```

#### Running Tests

```bash
python test_rsa.py
```

#### Running Examples

```bash
python example_usage.py
```

### Implementation Details

#### Montgomery Algorithm

The Montgomery algorithm provides efficient modular multiplication and exponentiation by:

1. **Montgomery Form Conversion**: Converting numbers to Montgomery form (a × R mod n)
2. **Montgomery Reduction**: Efficient reduction operation to compute (a × R⁻¹) mod n
3. **Montgomery Multiplication**: Fast multiplication in Montgomery domain
4. **Montgomery Exponentiation**: Binary exponentiation using Montgomery arithmetic

#### Key Components

- **MontgomeryRSA Class**: Main RSA implementation
- **Montgomery Parameters**: Automatic calculation of R and n' for given modulus
- **Modular Exponentiation**: Efficient computation of a^b mod n
- **Text Encoding**: Helper functions for string-to-integer conversion

### Mathematical Background

RSA encryption/decryption relies on:
- **Encryption**: c = m^e mod n
- **Decryption**: m = c^d mod n

Montgomery algorithm optimizes modular exponentiation by:
- Working in Montgomery domain to avoid expensive division operations
- Using efficient reduction techniques
- Minimizing the number of modular reductions needed

### Performance

For 256-bit keys, the Montgomery implementation provides correct results matching the standard Python `pow()` function. For larger key sizes (1024+ bits), Montgomery algorithm typically shows significant performance benefits due to reduced computational complexity.

### Security Note

This implementation is for educational purposes. For production use, consider:
- Secure random number generation for keys
- Proper padding schemes (OAEP, PKCS#1)
- Side-channel attack protections
- Constant-time implementations