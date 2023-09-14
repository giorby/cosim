-- -------------------------------------------------------------
--
-- Module: lowpass
-- Generated by MATLAB(R) 9.14 and Filter Design HDL Coder 3.1.13.
-- Generated on: 2023-09-08 19:05:46
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- HDL Code Generation Options:
--
-- TargetLanguage: VHDL
-- Name: lowpass
-- TestBenchName: lowpass_tb
-- TestBenchStimulus: step ramp chirp 

-- Filter Specifications:
--
-- Sample Rate     : 100 kHz
-- Response        : Lowpass
-- Specification   : N,Fp,Ap,Ast
-- Passband Edge   : 5 kHz
-- Passband Ripple : 0.5 dB
-- Filter Order    : 4
-- Stopband Atten. : 60 dB
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- HDL Implementation    : Fully parallel
-- Folding Factor        : 1
-- -------------------------------------------------------------
-- Filter Settings:
--
-- Discrete-Time IIR Filter (real)
-- -------------------------------
-- Filter Structure    : Direct-Form II, Second-Order Sections
-- Number of Sections  : 2
-- Stable              : Yes
-- Linear Phase        : No
-- -------------------------------------------------------------



LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.ALL;

ENTITY lowpass IS
   PORT( clk                             :   IN    std_logic; 
         clk_enable                      :   IN    std_logic; 
         reset                           :   IN    std_logic; 
         filter_in                       :   IN    real; -- double
         filter_out                      :   OUT   real  -- double
         );

END lowpass;


----------------------------------------------------------------
--Module Architecture: lowpass
----------------------------------------------------------------
ARCHITECTURE rtl OF lowpass IS
  -- Local Functions
  -- Type Definitions
  TYPE delay_pipeline_type IS ARRAY (NATURAL range <>) OF real; -- double
  -- Constants
  CONSTANT scaleconst1                    : real := 2.9976619221815000E-02; -- double
  CONSTANT coeff_b1_section1              : real := 1.4512925247604927E-01; -- double
  CONSTANT coeff_b2_section1              : real := -1.8976443564817516E-01; -- double
  CONSTANT coeff_b3_section1              : real := 1.4512925247604927E-01; -- double
  CONSTANT coeff_a2_section1              : real := -1.8057476739787599E+00; -- double
  CONSTANT coeff_a3_section1              : real := 9.0470757680961666E-01; -- double
  CONSTANT coeff_b1_section2              : real := 4.8516689753535464E-01; -- double
  CONSTANT coeff_b2_section2              : real := 7.1017658668477757E-02; -- double
  CONSTANT coeff_b3_section2              : real := 4.8516689753535475E-01; -- double
  CONSTANT coeff_a2_section2              : real := -1.7270234562463465E+00; -- double
  CONSTANT coeff_a3_section2              : real := 7.6060194538848092E-01; -- double
  -- Signals
  SIGNAL input_register                   : real := 0.0; -- double
  SIGNAL scale1                           : real := 0.0; -- double
  SIGNAL scaletypeconvert1                : real := 0.0; -- double
  -- Section 1 Signals 
  SIGNAL a1sum1                           : real := 0.0; -- double
  SIGNAL a2sum1                           : real := 0.0; -- double
  SIGNAL b1sum1                           : real := 0.0; -- double
  SIGNAL b2sum1                           : real := 0.0; -- double
  SIGNAL delay_section1                   : delay_pipeline_type(0 TO 1) := (0.0, 0.0); -- double
  SIGNAL inputconv1                       : real := 0.0; -- double
  SIGNAL a2mul1                           : real := 0.0; -- double
  SIGNAL a3mul1                           : real := 0.0; -- double
  SIGNAL b1mul1                           : real := 0.0; -- double
  SIGNAL b2mul1                           : real := 0.0; -- double
  SIGNAL b3mul1                           : real := 0.0; -- double
  -- Section 2 Signals 
  SIGNAL a1sum2                           : real := 0.0; -- double
  SIGNAL a2sum2                           : real := 0.0; -- double
  SIGNAL b1sum2                           : real := 0.0; -- double
  SIGNAL b2sum2                           : real := 0.0; -- double
  SIGNAL delay_section2                   : delay_pipeline_type(0 TO 1) := (0.0, 0.0); -- double
  SIGNAL inputconv2                       : real := 0.0; -- double
  SIGNAL a2mul2                           : real := 0.0; -- double
  SIGNAL a3mul2                           : real := 0.0; -- double
  SIGNAL b1mul2                           : real := 0.0; -- double
  SIGNAL b2mul2                           : real := 0.0; -- double
  SIGNAL b3mul2                           : real := 0.0; -- double
  SIGNAL output_typeconvert               : real := 0.0; -- double
  SIGNAL output_register                  : real := 0.0; -- double


BEGIN

  -- Block Statements
  input_reg_process : PROCESS (clk, reset)
  BEGIN
    IF reset = '1' THEN
      input_register <= 0.0000000000000000E+00;
    ELSIF clk'event AND clk = '1' THEN
      IF clk_enable = '1' THEN
        input_register <= filter_in;
      END IF;
    END IF; 
  END PROCESS input_reg_process;

  scale1 <= input_register * scaleconst1;

  scaletypeconvert1 <= scale1;


  --   ------------------ Section 1 ------------------

  delay_process_section1 : PROCESS (clk, reset)
  BEGIN
    IF reset = '1' THEN
      delay_section1(0) <= 0.0000000000000000E+00;
      delay_section1(1) <= 0.0000000000000000E+00;
    ELSIF clk'event AND clk = '1' THEN
      IF clk_enable = '1' THEN
        delay_section1(1) <= delay_section1(0);
        delay_section1(0) <= a1sum1;
      END IF;
    END IF;
  END PROCESS delay_process_section1;

  inputconv1 <= scaletypeconvert1;


  a2mul1 <= delay_section1(0) * coeff_a2_section1;

  a3mul1 <= delay_section1(1) * coeff_a3_section1;

  b1mul1 <= a1sum1 * coeff_b1_section1;

  b2mul1 <= delay_section1(0) * coeff_b2_section1;

  b3mul1 <= delay_section1(1) * coeff_b3_section1;

  a2sum1 <= inputconv1 - a2mul1;

  a1sum1 <= a2sum1 - a3mul1;

  b2sum1 <= b1mul1 + b2mul1;

  b1sum1 <= b2sum1 + b3mul1;

  --   ------------------ Section 2 ------------------

  delay_process_section2 : PROCESS (clk, reset)
  BEGIN
    IF reset = '1' THEN
      delay_section2(0) <= 0.0000000000000000E+00;
      delay_section2(1) <= 0.0000000000000000E+00;
    ELSIF clk'event AND clk = '1' THEN
      IF clk_enable = '1' THEN
        delay_section2(1) <= delay_section2(0);
        delay_section2(0) <= a1sum2;
      END IF;
    END IF;
  END PROCESS delay_process_section2;

  inputconv2 <= b1sum1;


  a2mul2 <= delay_section2(0) * coeff_a2_section2;

  a3mul2 <= delay_section2(1) * coeff_a3_section2;

  b1mul2 <= a1sum2 * coeff_b1_section2;

  b2mul2 <= delay_section2(0) * coeff_b2_section2;

  b3mul2 <= delay_section2(1) * coeff_b3_section2;

  a2sum2 <= inputconv2 - a2mul2;

  a1sum2 <= a2sum2 - a3mul2;

  b2sum2 <= b1mul2 + b2mul2;

  b1sum2 <= b2sum2 + b3mul2;

  output_typeconvert <= b1sum2;


  Output_Register_process : PROCESS (clk, reset)
  BEGIN
    IF reset = '1' THEN
      output_register <= 0.0000000000000000E+00;
    ELSIF clk'event AND clk = '1' THEN
      IF clk_enable = '1' THEN
        output_register <= output_typeconvert;
      END IF;
    END IF; 
  END PROCESS Output_Register_process;

  -- Assignment Statements
  filter_out <= output_register;
END rtl;
