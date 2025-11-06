#!/usr/bin/env python3
"""
Test suite for Chadsys - Digital Design Systems Project

This module contains comprehensive tests for the Chadsys digital system
to ensure all operations work correctly.
"""

import unittest
import sys
import os

# Add the project root to the path so we can import chadsys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from chadsys import Chadsys


class TestChadsys(unittest.TestCase):
    """Test cases for the Chadsys digital system."""
    
    def setUp(self):
        """Set up test fixtures before each test method."""
        self.system = Chadsys()
    
    def test_initialization(self):
        """Test that the system initializes correctly."""
        self.assertEqual(self.system.name, "Chadsys")
        self.assertEqual(self.system.version, "1.0.0")
        self.assertEqual(self.system.register_a, 0)
        self.assertEqual(self.system.register_b, 0)
        self.assertEqual(self.system.result_register, 0)
        self.assertFalse(self.system.status_flags['zero'])
        self.assertFalse(self.system.status_flags['carry'])
        self.assertFalse(self.system.status_flags['overflow'])
        self.assertFalse(self.system.status_flags['negative'])
    
    def test_load_registers(self):
        """Test loading values into registers."""
        # Test loading register A
        result = self.system.load_register_a(42)
        self.assertEqual(result, 42)
        self.assertEqual(self.system.register_a, 42)
        
        # Test loading register B
        result = self.system.load_register_b(100)
        self.assertEqual(result, 100)
        self.assertEqual(self.system.register_b, 100)
        
        # Test loading large values (32-bit limit)
        large_value = 0xFFFFFFFF
        result = self.system.load_register_a(large_value)
        self.assertEqual(result, large_value)
        
        # Test overflow handling
        overflow_value = 0x1FFFFFFFF  # Larger than 32-bit
        result = self.system.load_register_a(overflow_value)
        self.assertEqual(result, 0xFFFFFFFF)  # Should be truncated to 32-bit
    
    def test_addition(self):
        """Test addition operations."""
        # Basic addition
        result = self.system.add(10, 20)
        self.assertEqual(result, 30)
        self.assertEqual(self.system.result_register, 30)
        
        # Addition using registers
        self.system.load_register_a(15)
        self.system.load_register_b(25)
        result = self.system.add()
        self.assertEqual(result, 40)
        
        # Test carry flag
        result = self.system.add(0xFFFFFFFF, 1)
        self.assertEqual(result, 0)  # Overflow wraps around
        self.assertTrue(self.system.status_flags['carry'])
        self.assertTrue(self.system.status_flags['zero'])
    
    def test_subtraction(self):
        """Test subtraction operations."""
        # Basic subtraction
        result = self.system.subtract(50, 20)
        self.assertEqual(result, 30)
        
        # Subtraction resulting in negative (two's complement)
        result = self.system.subtract(10, 20)
        expected = (1 << 32) - 10  # Two's complement representation
        self.assertEqual(result, expected)
        self.assertTrue(self.system.status_flags['carry'])  # Borrow occurred
    
    def test_logical_operations(self):
        """Test logical operations."""
        # AND operation
        result = self.system.logical_and(0xFF, 0x0F)
        self.assertEqual(result, 0x0F)
        
        # OR operation
        result = self.system.logical_or(0xFF, 0x0F)
        self.assertEqual(result, 0xFF)
        
        # XOR operation
        result = self.system.logical_xor(0xFF, 0x0F)
        self.assertEqual(result, 0xF0)
        
        # NOT operation
        result = self.system.logical_not(0xFF)
        self.assertEqual(result, 0xFFFFFF00)
    
    def test_shift_operations(self):
        """Test shift operations."""
        # Left shift
        result = self.system.shift_left(0x01, 1)
        self.assertEqual(result, 0x02)
        
        result = self.system.shift_left(0x01, 8)
        self.assertEqual(result, 0x100)
        
        # Right shift
        result = self.system.shift_right(0x100, 1)
        self.assertEqual(result, 0x80)
        
        result = self.system.shift_right(0x100, 8)
        self.assertEqual(result, 0x01)
    
    def test_status_flags(self):
        """Test status flag updates."""
        # Zero flag
        self.system.add(0, 0)
        self.assertTrue(self.system.status_flags['zero'])
        
        # Non-zero result
        self.system.add(1, 1)
        self.assertFalse(self.system.status_flags['zero'])
        
        # Negative flag (MSB set)
        self.system.load_register_a(0x80000000)
        self.assertTrue(self.system.status_flags['negative'])
        
        # Positive number
        self.system.load_register_a(0x7FFFFFFF)
        self.assertFalse(self.system.status_flags['negative'])
    
    def test_system_status(self):
        """Test getting system status."""
        self.system.load_register_a(100)
        self.system.load_register_b(200)
        self.system.add()
        
        status = self.system.get_status()
        self.assertEqual(status['register_a'], 100)
        self.assertEqual(status['register_b'], 200)
        self.assertEqual(status['result'], 300)
        self.assertIsInstance(status['flags'], dict)
    
    def test_system_reset(self):
        """Test system reset functionality."""
        # Set some values
        self.system.load_register_a(100)
        self.system.load_register_b(200)
        self.system.add()
        
        # Reset system
        self.system.reset()
        
        # Check everything is reset
        self.assertEqual(self.system.register_a, 0)
        self.assertEqual(self.system.register_b, 0)
        self.assertEqual(self.system.result_register, 0)
        self.assertFalse(self.system.status_flags['zero'])
        self.assertFalse(self.system.status_flags['carry'])
        self.assertFalse(self.system.status_flags['overflow'])
        self.assertFalse(self.system.status_flags['negative'])
    
    def test_32bit_limits(self):
        """Test 32-bit register limits."""
        # Maximum 32-bit value
        max_val = 0xFFFFFFFF
        self.system.load_register_a(max_val)
        self.assertEqual(self.system.register_a, max_val)
        
        # Test overflow truncation
        overflow_val = 0x1FFFFFFFF
        self.system.load_register_a(overflow_val)
        self.assertEqual(self.system.register_a, max_val)  # Should be truncated
    
    def test_complex_operations(self):
        """Test complex operation sequences."""
        # Load values and perform multiple operations
        self.system.load_register_a(0xAAAA)
        self.system.load_register_b(0x5555)
        
        # XOR should give all 1s in the lower 16 bits
        result = self.system.logical_xor()
        self.assertEqual(result, 0xFFFF)
        
        # Shift left by 16 positions
        result = self.system.shift_left(result, 16)
        self.assertEqual(result, 0xFFFF0000)


class TestChadsysUtilityFunctions(unittest.TestCase):
    """Test utility functions in the chadsys module."""
    
    def test_parse_value(self):
        """Test the parse_value utility function."""
        from chadsys import parse_value
        
        # Test decimal parsing
        self.assertEqual(parse_value("123"), 123)
        self.assertEqual(parse_value("0"), 0)
        
        # Test hexadecimal parsing
        self.assertEqual(parse_value("0x10"), 16)
        self.assertEqual(parse_value("0xFF"), 255)
        self.assertEqual(parse_value("0xABCD"), 43981)
        
        # Test case insensitivity
        self.assertEqual(parse_value("0XFF"), 255)
        self.assertEqual(parse_value("0xff"), 255)
        
        # Test invalid values
        with self.assertRaises(ValueError):
            parse_value("invalid")
        
        with self.assertRaises(ValueError):
            parse_value("0xZZ")


def run_tests():
    """Run all tests and display results."""
    print("Running Chadsys Test Suite")
    print("=" * 50)
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test cases
    suite.addTests(loader.loadTestsFromTestCase(TestChadsys))
    suite.addTests(loader.loadTestsFromTestCase(TestChadsysUtilityFunctions))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Print summary
    print("\n" + "=" * 50)
    if result.wasSuccessful():
        print("✓ All tests passed!")
    else:
        print(f"✗ {len(result.failures)} test(s) failed")
        print(f"✗ {len(result.errors)} error(s) occurred")
    
    return result.wasSuccessful()


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)