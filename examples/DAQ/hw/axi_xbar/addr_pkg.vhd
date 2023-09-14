-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl_modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://gitlab.com/hdl_modules/hdl_modules
-- -------------------------------------------------------------------------------------------------
-- Collection of types/functions for working with address decode/matching.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library math;
use math.math_pkg.all;


package addr_pkg is

  constant addr_width : positive := 32;
  subtype addr_t is u_unsigned(addr_width - 1 downto 0);
  type addr_vec_t is array (integer range <>) of addr_t;
  function to_addr(value : natural) return addr_t;

  type addr_and_mask_t is record
    addr : addr_t;
    mask : addr_t;
  end record;
  type addr_and_mask_vec_t is array (integer range <>) of addr_and_mask_t;

  function addr_bits_needed(addrs : addr_and_mask_vec_t) return positive;

  function match(addr : u_unsigned; addr_and_mask : addr_and_mask_t) return boolean;

  function decode(addr : u_unsigned; addrs : addr_and_mask_vec_t) return natural;

end package;

package body addr_pkg is

  function to_addr(value : natural) return addr_t is
    constant result : addr_t := to_unsigned(value, addr_width);
  begin
    return result;
  end function;

  function addr_bits_needed(addrs : addr_and_mask_vec_t) return positive is
    variable result : positive := 1;
  begin
    -- Return the number of bits that are needed to decode and handle the addresses.
    for addr_idx in addrs'range loop
      result := maximum(result, num_bits_needed(addrs(addr_idx).mask));
    end loop;
    return result;
  end function;

  function match(addr : u_unsigned; addr_and_mask : addr_and_mask_t) return boolean is
    variable test_ok : boolean := true;
  begin
    for bit_idx in addr_and_mask.addr'range loop
      if addr_and_mask.mask(bit_idx) then
        test_ok := test_ok and (addr(bit_idx) = addr_and_mask.addr(bit_idx));
      end if;
    end loop;

    return test_ok;
  end function;

  function decode(addr : u_unsigned; addrs : addr_and_mask_vec_t) return natural is
    constant decode_fail : natural := addrs'length;
  begin
    for addr_idx in addrs'range loop
      if match(addr, addrs(addr_idx)) then
        return addr_idx;
      end if;
    end loop;

    return decode_fail;
  end function;

end package body;
