#!/usr/bin/env python3
"""
Chadsys - A Digital Design Systems Project

A simple digital computation system that demonstrates basic digital design concepts
including arithmetic operations, logical operations, and binary manipulations.

Author: DDS1 Project
"""

class Chadsys:
    """
    Chadsys - Core digital system class
    
    This class implements a basic digital system with computational capabilities
    including arithmetic, logical, and binary operations.
    """
    
    def __init__(self):
        """Initialize the Chadsys system."""
        self.name = "Chadsys"
        self.version = "1.0.0"
        self.register_a = 0
        self.register_b = 0
        self.result_register = 0
        self.status_flags = {
            'zero': False,
            'carry': False,
            'overflow': False,
            'negative': False
        }
    
    def load_register_a(self, value):
        """Load a value into register A."""
        self.register_a = value & 0xFFFFFFFF  # 32-bit register
        self._update_flags(self.register_a)
        return self.register_a
    
    def load_register_b(self, value):
        """Load a value into register B."""
        self.register_b = value & 0xFFFFFFFF  # 32-bit register
        self._update_flags(self.register_b)
        return self.register_b
    
    def _update_flags(self, value):
        """Update status flags based on the result value."""
        self.status_flags['zero'] = (value == 0)
        self.status_flags['negative'] = (value & 0x80000000) != 0
    
    def add(self, a=None, b=None):
        """Perform addition operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        if b is not None:
            self.register_b = b & 0xFFFFFFFF
        
        result = self.register_a + self.register_b
        self.status_flags['carry'] = result > 0xFFFFFFFF
        self.status_flags['overflow'] = self._check_overflow_add(self.register_a, self.register_b, result)
        
        self.result_register = result & 0xFFFFFFFF
        self._update_flags(self.result_register)
        return self.result_register
    
    def subtract(self, a=None, b=None):
        """Perform subtraction operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        if b is not None:
            self.register_b = b & 0xFFFFFFFF
        
        result = self.register_a - self.register_b
        self.status_flags['carry'] = result < 0
        
        if result < 0:
            result = (1 << 32) + result  # Two's complement representation
        
        self.result_register = result & 0xFFFFFFFF
        self._update_flags(self.result_register)
        return self.result_register
    
    def logical_and(self, a=None, b=None):
        """Perform logical AND operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        if b is not None:
            self.register_b = b & 0xFFFFFFFF
        
        self.result_register = self.register_a & self.register_b
        self._update_flags(self.result_register)
        return self.result_register
    
    def logical_or(self, a=None, b=None):
        """Perform logical OR operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        if b is not None:
            self.register_b = b & 0xFFFFFFFF
        
        self.result_register = self.register_a | self.register_b
        self._update_flags(self.result_register)
        return self.result_register
    
    def logical_xor(self, a=None, b=None):
        """Perform logical XOR operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        if b is not None:
            self.register_b = b & 0xFFFFFFFF
        
        self.result_register = self.register_a ^ self.register_b
        self._update_flags(self.result_register)
        return self.result_register
    
    def logical_not(self, a=None):
        """Perform logical NOT operation on register A."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        
        self.result_register = (~self.register_a) & 0xFFFFFFFF
        self._update_flags(self.result_register)
        return self.result_register
    
    def shift_left(self, a=None, positions=1):
        """Perform left shift operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        
        self.result_register = (self.register_a << positions) & 0xFFFFFFFF
        self._update_flags(self.result_register)
        return self.result_register
    
    def shift_right(self, a=None, positions=1):
        """Perform right shift operation."""
        if a is not None:
            self.register_a = a & 0xFFFFFFFF
        
        self.result_register = self.register_a >> positions
        self._update_flags(self.result_register)
        return self.result_register
    
    def _check_overflow_add(self, a, b, result):
        """Check for overflow in addition."""
        # Check if signs of operands are same and result has different sign
        a_sign = a & 0x80000000
        b_sign = b & 0x80000000
        result_sign = result & 0x80000000
        
        return (a_sign == b_sign) and (a_sign != result_sign)
    
    def get_status(self):
        """Get current system status."""
        return {
            'register_a': self.register_a,
            'register_b': self.register_b,
            'result': self.result_register,
            'flags': self.status_flags.copy()
        }
    
    def reset(self):
        """Reset the system to initial state."""
        self.register_a = 0
        self.register_b = 0
        self.result_register = 0
        self.status_flags = {
            'zero': False,
            'carry': False,
            'overflow': False,
            'negative': False
        }


def main():
    """Main function for interactive command-line interface."""
    system = Chadsys()
    print(f"Welcome to {system.name} v{system.version}")
    print("Digital Design Systems - Interactive Mode")
    print("Type 'help' for available commands, 'quit' to exit\n")
    
    while True:
        try:
            command = input("chadsys> ").strip().lower()
            
            if command in ['quit', 'exit', 'q']:
                print("Goodbye!")
                break
            
            elif command == 'help':
                print_help()
            
            elif command == 'status':
                print_status(system)
            
            elif command == 'reset':
                system.reset()
                print("System reset.")
            
            elif command.startswith('load'):
                handle_load_command(system, command)
            
            elif command.startswith('add'):
                handle_arithmetic_command(system, command, 'add')
            
            elif command.startswith('sub'):
                handle_arithmetic_command(system, command, 'subtract')
            
            elif command.startswith('and'):
                handle_arithmetic_command(system, command, 'logical_and')
            
            elif command.startswith('or'):
                handle_arithmetic_command(system, command, 'logical_or')
            
            elif command.startswith('xor'):
                handle_arithmetic_command(system, command, 'logical_xor')
            
            elif command.startswith('not'):
                result = system.logical_not()
                print(f"Result: {result} (0x{result:08x})")
            
            elif command.startswith('shl'):
                handle_shift_command(system, command, 'left')
            
            elif command.startswith('shr'):
                handle_shift_command(system, command, 'right')
            
            else:
                print("Unknown command. Type 'help' for available commands.")
        
        except KeyboardInterrupt:
            print("\nGoodbye!")
            break
        except Exception as e:
            print(f"Error: {e}")


def print_help():
    """Print help information."""
    print("""
Available Commands:
  help              - Show this help message
  status            - Show current system status
  reset             - Reset system to initial state
  quit/exit/q       - Exit the system
  
  load a <value>    - Load value into register A
  load b <value>    - Load value into register B
  
  add [a] [b]       - Add values (uses registers if no args)
  sub [a] [b]       - Subtract values (uses registers if no args)
  and [a] [b]       - Logical AND (uses registers if no args)
  or [a] [b]        - Logical OR (uses registers if no args)
  xor [a] [b]       - Logical XOR (uses registers if no args)
  not [a]           - Logical NOT of register A
  
  shl [a] [pos]     - Shift left (default 1 position)
  shr [a] [pos]     - Shift right (default 1 position)

Values can be decimal or hexadecimal (prefix with 0x)
""")


def print_status(system):
    """Print current system status."""
    status = system.get_status()
    print(f"""
System Status:
  Register A: {status['register_a']} (0x{status['register_a']:08x})
  Register B: {status['register_b']} (0x{status['register_b']:08x})
  Result:     {status['result']} (0x{status['result']:08x})
  
  Flags:
    Zero:     {status['flags']['zero']}
    Carry:    {status['flags']['carry']}
    Overflow: {status['flags']['overflow']}
    Negative: {status['flags']['negative']}
""")


def handle_load_command(system, command):
    """Handle load register commands."""
    parts = command.split()
    if len(parts) < 3:
        print("Usage: load <a|b> <value>")
        return
    
    register = parts[1].lower()
    try:
        value = parse_value(parts[2])
        if register == 'a':
            system.load_register_a(value)
            print(f"Loaded {value} into register A")
        elif register == 'b':
            system.load_register_b(value)
            print(f"Loaded {value} into register B")
        else:
            print("Invalid register. Use 'a' or 'b'.")
    except ValueError:
        print("Invalid value. Use decimal or hexadecimal (0x prefix).")


def handle_arithmetic_command(system, command, operation):
    """Handle arithmetic and logical operation commands."""
    parts = command.split()
    a_val = None
    b_val = None
    
    try:
        if len(parts) >= 2:
            a_val = parse_value(parts[1])
        if len(parts) >= 3:
            b_val = parse_value(parts[2])
        
        result = getattr(system, operation)(a_val, b_val)
        print(f"Result: {result} (0x{result:08x})")
        
    except ValueError:
        print("Invalid value. Use decimal or hexadecimal (0x prefix).")


def handle_shift_command(system, command, direction):
    """Handle shift operation commands."""
    parts = command.split()
    a_val = None
    positions = 1
    
    try:
        if len(parts) >= 2:
            a_val = parse_value(parts[1])
        if len(parts) >= 3:
            positions = int(parts[2])
        
        if direction == 'left':
            result = system.shift_left(a_val, positions)
        else:
            result = system.shift_right(a_val, positions)
        
        print(f"Result: {result} (0x{result:08x})")
        
    except ValueError:
        print("Invalid value. Use decimal or hexadecimal (0x prefix).")


def parse_value(value_str):
    """Parse a value string as decimal or hexadecimal."""
    if value_str.lower().startswith('0x'):
        return int(value_str, 16)
    else:
        return int(value_str)


if __name__ == "__main__":
    main()