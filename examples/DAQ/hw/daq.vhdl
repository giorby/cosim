-- DAQ peripheral implementation.
--
-- Copyright © 2023 Giorgio Biagetti <g.biagetti@staff.univpm.it>
-- Department of Information Engineering
-- Università Politecnica delle Marche (ITALY)
--
-- SPDX-License-Identifier: CERN-OHL-W-2.0

library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity DAQ is
	generic (
		C_S_AXI_DATA_WIDTH : integer := 32;
		C_S_AXI_ADDR_WIDTH : integer := 5
	);
	port (
		-- ADC control signals:
		mem_bank        : in  std_logic;
		mem_enable      : out std_logic;
		mem_interrupt   : out std_logic;
		------------------------------------------------------------------------
		-- AXI subordinate bus:
		------------------------------------------------------------------------
		S_AXI_ACLK      : in  std_logic;
		S_AXI_ARESETN   : in  std_logic;
		S_AXI_AWADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
		S_AXI_AWPROT    : in  std_logic_vector(2 downto 0);
		S_AXI_AWVALID   : in  std_logic;
		S_AXI_AWREADY   : out std_logic;
		S_AXI_WDATA     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
		S_AXI_WSTRB     : in  std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);
		S_AXI_WVALID    : in  std_logic;
		S_AXI_WREADY    : out std_logic;
		S_AXI_BRESP     : out std_logic_vector(1 downto 0);
		S_AXI_BVALID    : out std_logic;
		S_AXI_BREADY    : in  std_logic;
		S_AXI_ARADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
		S_AXI_ARPROT    : in  std_logic_vector(2 downto 0);
		S_AXI_ARVALID   : in  std_logic;
		S_AXI_ARREADY   : out std_logic;
		S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
		S_AXI_RRESP     : out std_logic_vector(1 downto 0);
		S_AXI_RVALID    : out std_logic;
		S_AXI_RREADY    : in  std_logic
		------------------------------------------------------------------------
	);
end DAQ;

architecture behavioural of DAQ is
	-- AXI4LITE signals:
	-- write channels:
	signal axi_waddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1   downto 0);
	signal axi_wdata   : std_logic_vector(C_S_AXI_DATA_WIDTH-1   downto 0);
	signal axi_wstrb   : std_logic_vector(C_S_AXI_DATA_WIDTH/8-1 downto 0);
	signal axi_awready : std_logic;
	signal axi_wready  : std_logic;
	signal axi_bresp   : std_logic_vector(1 downto 0);
	signal axi_bvalid  : std_logic;
	-- read channels:
	signal axi_raddr   : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_rdata   : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal axi_arready : std_logic;
	signal axi_rresp   : std_logic_vector(1 downto 0);
	signal axi_rvalid  : std_logic;

	signal got_raddr   : std_logic;
	signal got_waddr   : std_logic;
	signal got_wdata   : std_logic;

	-- registers:
	signal reg_adc_control : std_logic_vector( 7 downto 0);
	-- ADC control internal signals:
	signal old_bank        : std_logic;

begin
	-- IRQ output:
	mem_interrupt <= reg_adc_control(5) and reg_adc_control(4);

	-- AXI handling:

	S_AXI_AWREADY <= axi_awready;
	S_AXI_WREADY  <= axi_wready;
	S_AXI_BVALID  <= axi_bvalid;
	S_AXI_BRESP   <= axi_bresp;

	S_AXI_ARREADY <= axi_arready;
	S_AXI_RDATA   <= axi_rdata;
	S_AXI_RRESP   <= axi_rresp;
	S_AXI_RVALID  <= axi_rvalid;

	writes : process (S_AXI_ACLK) is
		variable done : boolean;
		-- ADC procedures:
		-- reg_adc_control bit-fields:
		--   [7]  EN    enable
		--   [6]  COCO  continuous
		--   [5]  IE    irq_enable
		--   [4]  IF    irq_flag
		--  [3:2]       (unused)
		--  [1:0] B     bank_ready

		procedure reg_adc_reset is
		begin
			reg_adc_control <= (others => '0');
			old_bank <= '0';
		end procedure;

		procedure reg_adc_write (
			signal data : in std_logic_vector(7 downto 0);
			signal mask : in std_logic_vector
		) is
		begin
			if mask = "0" then return; end if;
			mem_enable <= data(7);
			reg_adc_control(7 downto 5) <= data(7 downto 5);
			if data(4) = '1' then
				reg_adc_control(4) <= '0';
			end if;
			if data(7) = '0' then
				reg_adc_control(4) <= '0';
				reg_adc_control(1 downto 0) <= b"00";
			end if;
		end procedure;

		procedure reg_adc_clock is
		begin
			old_bank <= mem_bank;
			if mem_bank /= old_bank then
				if reg_adc_control(6) = '1' then -- COCO (continuous conversion)
					if old_bank = '0' then
						reg_adc_control(1 downto 0) <= b"01";
					else
						reg_adc_control(1 downto 0) <= b"10";
					end if;
					reg_adc_control(4) <= '1'; -- irq_flag
					else
					if old_bank = '0' then
						reg_adc_control(1 downto 0) <= b"01";
					else
						reg_adc_control(1 downto 0) <= b"11";
						reg_adc_control(4) <= '1';
						reg_adc_control(7) <= '0'; -- EN
						mem_enable <= '0';
					end if;
				end if;
			end if;
		end procedure;
	begin
		if rising_edge(S_AXI_ACLK) then
			if S_AXI_ARESETN = '0' then
				axi_awready <= '0';
				axi_wready  <= '0';
				axi_bvalid  <= '0';
				got_waddr   <= '0';
				got_wdata   <= '0';
				reg_adc_reset;
			else
				reg_adc_clock;

				-- address handshake:
				if S_AXI_AWVALID = '1' and axi_awready = '1' then
					axi_waddr   <= S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto 0);
					got_waddr   <= '1';
					axi_awready <= '0';
				else
					axi_awready <= not got_waddr;
				end if;

				-- data handshake:
				if S_AXI_WVALID = '1' and axi_wready = '1' then
					axi_wdata   <= S_AXI_WDATA;
					axi_wstrb   <= S_AXI_WSTRB;
					got_wdata   <= '1';
					axi_wready  <= '0';
				else
					axi_wready  <= not got_wdata;
				end if;

				-- response handshake:
				if S_AXI_BREADY = '1' and axi_bvalid = '1' then
					axi_bvalid <= '0';
				end if;

				-- register write handling:
				done := false;
				if got_waddr = '1' and got_wdata = '1' then
					axi_bresp <= b"00";
					case axi_waddr(4 downto 2) is
					when b"000" =>
						reg_adc_write(axi_wdata(7 downto 0), axi_wstrb(0 downto 0));
						done := true;
					when others =>
						axi_bresp <= b"11";
						done := true;
					end case;
					if done then
						axi_bvalid <= '1';
						got_wdata <= '0';
						got_waddr <= '0';
					end if;
				end if;

			end if;
		end if;
	end process;

	reads : process (S_AXI_ACLK) is
	begin
		if rising_edge(S_AXI_ACLK) then
			if S_AXI_ARESETN = '0' then
				axi_arready <= '0';
				axi_rvalid  <= '0';
				got_raddr   <= '0';
			else
				-- address handshake:
				if S_AXI_ARVALID = '1' and axi_arready = '1' then
					axi_raddr   <= S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH-1 downto 0);
					got_raddr   <= '1';
					axi_arready <= '0';
				else
					axi_arready <= not got_raddr;
				end if;

				-- response handshake:
				if S_AXI_RREADY = '1' and axi_rvalid = '1' then
					axi_rvalid <= '0';
					got_raddr <= '0';
				else

				-- register read handling:
				if got_raddr = '1' then
					case axi_raddr(4 downto 2) is
					when b"000" =>
						axi_rresp <= b"00";
						axi_rdata <= X"000000" & reg_adc_control;
						axi_rvalid <= '1';
					when others =>
						axi_rresp <= b"11";
						axi_rdata <= X"00000000";
						axi_rvalid <= '1';
					end case;
				end if;
				end if;
			end if;
		end if;
	end process;

end behavioural;


----------------------------------------------------------------------------------


library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;

entity mem_writer is
	port (
		clk : in  std_logic;
		A   : out std_logic_vector (15 downto 0);
		D   : out std_logic_vector (31 downto 0);
		EN  : out std_logic;
		RST : out std_logic;
		WE  : out std_logic_vector (3 downto 0);
		data_input : in std_logic_vector (127 downto 0);
		data_valid : in std_logic;
		enable     : in std_logic
	);
end mem_writer;

architecture behavioral of mem_writer is
	signal phase : integer range 0 to 6 := 0;
	signal count : unsigned(15 downto 2) := (others => '0');
begin
	RST <= '0';
	WE  <= "1111";
	A   <= std_logic_vector(count) & B"00";

	writer : process (clk) is
	begin
		if rising_edge(clk) then
			if enable then
				case phase is
					when 0 =>
						if data_valid then
							phase <= 1;
						end if;
					when 1 =>
						EN <= '1';
						phase <= 2;
						D <= data_input(127 downto 96);
					when 2 =>
						phase <= 3;
						D <= data_input(95 downto 64);
						count <= count + 1;
					when 3 =>
						phase <= 4;
						D <= data_input(63 downto 32);
						count <= count + 1;
					when 4 =>
						phase <= 5;
						D <= data_input(31 downto 0);
						count <= count + 1;
					when 5 =>
						phase <= 6;
						EN <= '0';
						D  <= (others => '0');
						count <= count + 1;
					when 6 =>
						if not data_valid then
							phase <= 0;
						end if;
				end case;
			else
				count <= (others => '0');
				phase <= 0;
			end if;
		end if;
	end process;

end behavioral;


