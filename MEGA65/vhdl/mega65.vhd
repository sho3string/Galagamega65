----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework  
--
-- MEGA65 main file that contains the whole machine
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2021 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qnice_tools.all;

Library xpm;
use xpm.vcomponents.all;

entity MEGA65_Core is
generic (
   -- @TODO: Add your machine dependent generics of this core here or delete them, if there
   -- are no machine dependencies
   YOUR_GENERIC1  : natural;
   YOUR_GENERIC2  : string; 
   YOUR_GENERICN  : integer
);
port (
   CLK            : in std_logic;                  -- 100 MHz clock
   RESET_N        : in std_logic;                  -- CPU reset button

   -- Serial communication (rxd, txd only; rts/cts are not available)
   -- 115.200 baud, 8-N-1
   UART_RXD       : in std_logic;                  -- receive data
   UART_TXD       : out std_logic;                 -- send data

   -- VGA
   VGA_RED        : out std_logic_vector(7 downto 0);
   VGA_GREEN      : out std_logic_vector(7 downto 0);
   VGA_BLUE       : out std_logic_vector(7 downto 0);
   VGA_HS         : out std_logic;
   VGA_VS         : out std_logic;

   -- VDAC
   vdac_clk       : out std_logic;
   vdac_sync_n    : out std_logic;
   vdac_blank_n   : out std_logic;

   -- MEGA65 smart keyboard controller
   kb_io0         : out std_logic;                 -- clock to keyboard
   kb_io1         : out std_logic;                 -- data output to keyboard
   kb_io2         : in std_logic;                  -- data input from keyboard

   -- SD Card
   SD_RESET       : out std_logic;
   SD_CLK         : out std_logic;
   SD_MOSI        : out std_logic;
   SD_MISO        : in std_logic

   -- 3.5mm analog audio jack
--   pwm_l          : out std_logic;
--   pwm_r          : out std_logic;

--   -- Joysticks
--   joy_1_up_n     : in std_logic;
--   joy_1_down_n   : in std_logic;
--   joy_1_left_n   : in std_logic;
--   joy_1_right_n  : in std_logic;
--   joy_1_fire_n   : in std_logic;

--   joy_2_up_n     : in std_logic;
--   joy_2_down_n   : in std_logic;
--   joy_2_left_n   : in std_logic;
--   joy_2_right_n  : in std_logic;
--   joy_2_fire_n   : in std_logic
);
end MEGA65_Core;

architecture beh of MEGA65_Core is

-- QNICE Firmware: Use the regular QNICE "operating system" called "Monitor" while developing
-- and debugging and use the MiSTer2MEGA65 firmware in the release version
constant QNICE_FIRMWARE    : string  := "../../QNICE/monitor/monitor.rom";
--constant QNICE_FIRMWARE    : string  := "../m2m-rom/m2m-rom.rom";  

-- Clock speeds
constant QNICE_CLK_SPEED   : natural := 50_000_000;
constant CORE_CLK_SPEED    : natural := 40_000_000;   -- @TODO YOURCORE expects 40 MHz

-- Rendering constants
--    VGA_*   size of the final output on the screen
--    CORE_*  size of the input resolution coming from the core
-- @TODO: Currently, our scaling factor is hard coded to 4. We need to have a fractional scaler
-- and we need to define the appropriate constants here 
constant VGA_DX            : natural := 800;          -- SVGA mode 800 x 600 @ 60 Hz
constant VGA_DY            : natural := 600;          -- ditto
constant CORE_DX           : natural := 200;
constant CORE_DY           : natural := 150;
constant CORE_TO_VGA_SCALE : natural := 4;

-- Constants for VGA output
constant FONT_DX           : natural := 16;
constant FONT_DY           : natural := 16;
constant CHARS_DX          : natural := VGA_DX / FONT_DX;
constant CHARS_DY          : natural := VGA_DY / FONT_DY;
constant CHAR_MEM_SIZE     : natural := CHARS_DX * CHARS_DY;
constant VRAM_ADDR_WIDTH   : natural := f_log2(CHAR_MEM_SIZE);

-- Clocks
signal main_clk            : std_logic;               -- @TODO YOUR CORE's main clock @ 40.00 MHz
signal vga_pixelclk        : std_logic;               -- SVGA mode 800 x 600 @ 60 Hz: 40.00 MHz
signal qnice_clk           : std_logic;               -- QNICE main clock @ 50 MHz

---------------------------------------------------------------------------------------------
-- main_clk
---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

-- QNICE control signals (see also gbc.asm for more details)
signal qnice_qngbc_reset          : std_logic;
signal qnice_qngbc_pause          : std_logic;
signal qnice_qngbc_keyboard       : std_logic;
signal qnice_qngbc_joystick       : std_logic;
signal qnice_qngbc_color          : std_logic;
signal qnice_qngbc_joy_map        : std_logic_vector(1 downto 0);
signal qnice_qngbc_color_mode     : std_logic;
signal qnice_qngbc_keyb_matrix    : std_logic_vector(15 downto 0);

-- On-Screen-Menu (OSM)
signal qnice_osm_cfg_enable       : std_logic;
signal qnice_osm_cfg_xy           : std_logic_vector(15 downto 0);
signal qnice_osm_cfg_dxdy         : std_logic_vector(15 downto 0);
signal qnice_vram_addr            : std_logic_vector(15 downto 0);
signal qnice_vram_data_out        : std_logic_vector(15 downto 0);
signal qnice_vram_attr_we         : std_logic;
signal qnice_vram_attr_data_out_i : std_logic_vector(7 downto 0);
signal qnice_vram_we              : std_logic;
signal qnice_vram_data_out_i      : std_logic_vector(7 downto 0);

---------------------------------------------------------------------------------------------
-- vga_pixelclk
---------------------------------------------------------------------------------------------

-- Core frame buffer
signal vga_core_vram_addr  : std_logic_vector(14 downto 0);
signal vga_core_vram_data  : std_logic_vector(23 downto 0);

-- On-Screen-Menu (OSM)
signal vga_osm_cfg_enable : std_logic;
signal vga_osm_cfg_xy     : std_logic_vector(15 downto 0);
signal vga_osm_cfg_dxdy   : std_logic_vector(15 downto 0);
signal vga_osm_vram_addr  : std_logic_vector(15 downto 0);
signal vga_osm_vram_data  : std_logic_vector(7 downto 0);
signal vga_osm_vram_attr  : std_logic_vector(7 downto 0);

begin

   -- MMCME2_ADV clock generators:
   --    Core clock:          @TODO YOURCORE expects 40 MHz
   --    Pixelclock:          40 MHz
   --    QNICE co-processor:  50 MHz
   clk_gen : entity work.clk
      port map
      (
         sys_clk_i  => CLK,
         main_o     => main_clk,         -- @TODO YOURCORE expects 40 MHz
         qnice_o    => qnice_clk,        -- QNICE's 50 MHz main clock
         pixelclk_o => vga_pixelclk      -- 40.00 MHz pixelclock for SVGA mode 800 x 600 @ 60 Hz
      );

   ---------------------------------------------------------------------------------------------
   -- main_clk
   ---------------------------------------------------------------------------------------------

   i_main : entity work.main
      generic map (
         G_CORE_CLK_SPEED     => CORE_CLK_SPEED,
         
         -- Demo core specific generics @TODO not sure if you need them, too
         G_OUTPUT_DX          => VGA_DX,
         G_OUTPUT_DY          => VGA_DY,  
         
         -- @TODO feel free to add as many generics as your core needs
         -- you might also pass MEGA65 model specifics to your core, if needed (e.g. R2 vs. R3 differences) 
         G_YOUR_GENERIC1        => false,
         G_ANOTHER_THING        => 123456
      )
      port map (
         main_clk               => main_clk,
         reset_n                => reset_n,
         kb_io0                 => kb_io0,
         kb_io1                 => kb_io1,
         kb_io2                 => kb_io2
      );


   ---------------------------------------------------------------------------------------------
   -- qnice_clk
   ---------------------------------------------------------------------------------------------

   -- QNICE Co-Processor (System-on-a-Chip) for ROM loading and On-Screen-Menu
   QNICE_SOC : entity work.QNICE
      generic map
      (
         G_FIRMWARE              => QNICE_FIRMWARE,
         G_CHARS_DX              => CHARS_DX,
         G_CHARS_DY              => CHARS_DY
      )
      port map
      (
         CLK50                   => qnice_clk,        -- 50 MHz clock      -- input
         RESET_N                 => RESET_N,                               -- input

         -- serial communication (rxd, txd only; rts/cts are not available)
         -- 115.200 baud, 8-N-1
         UART_RXD                => UART_RXD,         -- receive data      -- input
         UART_TXD                => UART_TXD,         -- send data         -- output

         -- SD Card
         SD_RESET                => SD_RESET,                              -- output
         SD_CLK                  => SD_CLK,                                -- output
         SD_MOSI                 => SD_MOSI,                               -- output
         SD_MISO                 => SD_MISO,                               -- input

         gbc_osm                 => qnice_osm_cfg_enable,                  -- output
         osm_xy                  => qnice_osm_cfg_xy,                      -- output
         osm_dxdy                => qnice_osm_cfg_dxdy,                    -- output
         vram_addr               => qnice_vram_addr,                       -- output
         vram_data_out           => qnice_vram_data_out,                   -- output
         vram_attr_we            => qnice_vram_attr_we,                    -- output
         vram_attr_data_out_i    => qnice_vram_attr_data_out_i,            -- input
         vram_we                 => qnice_vram_we,                         -- output
         vram_data_out_i         => qnice_vram_data_out_i                  -- input
      );

   ---------------------------------------------------------------------------------------------
   -- vga_pixelclk
   ---------------------------------------------------------------------------------------------

   i_vga : entity work.vga
      generic map (
         G_VGA_DX             => VGA_DX,
         G_VGA_DY             => VGA_DY,
         G_CORE_DX            => CORE_DX,
         G_CORE_DY            => CORE_DY,
         G_CORE_TO_VGA_SCALE  => CORE_TO_VGA_SCALE
      )
      port map (
         clk_i                => vga_pixelclk,     -- pixel clock at frequency of VGA mode being used
         rst_i                => reset_n,          -- active low asycnchronous reset
         vga_osm_cfg_enable_i => vga_osm_cfg_enable,
         vga_osm_cfg_xy_i     => vga_osm_cfg_xy,
         vga_osm_cfg_dxdy_i   => vga_osm_cfg_dxdy,
         vga_osm_vram_addr_o  => vga_osm_vram_addr,
         vga_osm_vram_data_i  => vga_osm_vram_data,
         vga_osm_vram_attr_i  => vga_osm_vram_attr,
         vga_core_vram_addr_o => vga_core_vram_addr,
         vga_core_vram_data_i => vga_core_vram_data,
         vga_red_o            => vga_red,
         vga_green_o          => vga_green,
         vga_blue_o           => vga_blue,
         vga_hs_o             => vga_hs,
         vga_vs_o             => vga_vs,
         vdac_clk_o           => vdac_clk,
         vdac_sync_n_o        => vdac_sync_n,
         vdac_blank_n_o       => vdac_blank_n
      ); -- i_vga : entity work.vga


   ---------------------------------------------------------------------------------------------
   -- Dual Clocks
   ---------------------------------------------------------------------------------------------

--   i_qnice2main: xpm_cdc_array_single
--      generic map (
--         WIDTH => 56
--      )
--      port map (
--         src_clk                => qnice_clk,
--         src_in(0)              => qnice_qngbc_reset,
--         src_in(1)              => qnice_qngbc_pause,
--         src_in(2)              => qnice_qngbc_keyboard,
--         src_in(3)              => qnice_qngbc_joystick,
--         src_in(4)              => qnice_qngbc_color,
--         src_in(6 downto 5)     => qnice_qngbc_joy_map,
--         src_in(7)              => qnice_qngbc_color_mode,
--         src_in(15 downto 8)    => qnice_cart_cgb_flag,
--         src_in(23 downto 16)   => qnice_cart_sgb_flag,
--         src_in(31 downto 24)   => qnice_cart_mbc_type,
--         src_in(39 downto 32)   => qnice_cart_rom_size,
--         src_in(47 downto 40)   => qnice_cart_ram_size,
--         src_in(55 downto 48)   => qnice_cart_old_licensee,
--         dest_clk               => main_clk,
--         dest_out(0)            => main_qngbc_reset,
--         dest_out(1)            => main_qngbc_pause,
--         dest_out(2)            => main_qngbc_keyboard,
--         dest_out(3)            => main_qngbc_joystick,
--         dest_out(4)            => main_qngbc_color,
--         dest_out(6 downto 5)   => main_qngbc_joy_map,
--         dest_out(7)            => main_qngbc_color_mode,
--         dest_out(15 downto 8)  => main_cart_cgb_flag,
--         dest_out(23 downto 16) => main_cart_sgb_flag,
--         dest_out(31 downto 24) => main_cart_mbc_type,
--         dest_out(39 downto 32) => main_cart_rom_size,
--         dest_out(47 downto 40) => main_cart_ram_size,
--         dest_out(55 downto 48) => main_cart_old_licensee
--      ); -- i_qnice2main: xpm_cdc_array_single

--   i_main2qnice: xpm_cdc_array_single
--      generic map (
--         WIDTH => 16
--      )
--      port map (
--         src_clk                => main_clk,
--         src_in(15 downto 0)    => main_qngbc_keyb_matrix,
--         dest_clk               => qnice_clk,
--         dest_out(15 downto 0)  => qnice_qngbc_keyb_matrix
--      ); -- i_main2qnice: xpm_cdc_array_single

   i_qnice2vga: xpm_cdc_array_single
      generic map (
         WIDTH => 33
      )
      port map (
         src_clk                => qnice_clk,
         src_in(15 downto 0)    => qnice_osm_cfg_xy,
         src_in(31 downto 16)   => qnice_osm_cfg_dxdy,
         src_in(32)             => qnice_osm_cfg_enable,
         dest_clk               => vga_pixelclk,
         dest_out(15 downto 0)  => vga_osm_cfg_xy,
         dest_out(31 downto 16) => vga_osm_cfg_dxdy,
         dest_out(32)           => vga_osm_cfg_enable
      );
      
   -- Dual clock & dual port RAM that acts as framebuffer: the LCD display of the gameboy is
   -- written here by the GB core (using its local clock) and the VGA/HDMI display is being fed
   -- using the pixel clock
   core_frame_buffer : entity work.dualport_2clk_ram
      generic map
      (
         ADDR_WIDTH   => 15,
         DATA_WIDTH   => 24
      )
      port map
      (
--         clock_a      => main_clk,
--         address_a    => std_logic_vector(to_unsigned(main_pixel_out_ptr, 15)),
--         data_a       => main_pixel_out_data,
--         wren_a       => main_pixel_out_we,
--         q_a          => open,

         clock_b      => vga_pixelclk,
         address_b    => vga_core_vram_addr,
         data_b       => (others => '0'),
         wren_b       => '0',
         q_b          => vga_core_vram_data
      ); -- core_frame_buffer : entity work.dualport_2clk_ram

   -- Dual port & dual clock screen RAM / video RAM: contains the "ASCII" codes of the characters
   osm_vram : entity work.dualport_2clk_ram
      generic map
      (
         ADDR_WIDTH   => VRAM_ADDR_WIDTH,
         DATA_WIDTH   => 8,
         FALLING_A    => true              -- QNICE expects read/write to happen at the falling clock edge
      )
      port map
      (
         clock_a      => qnice_clk,
         address_a    => qnice_vram_addr(VRAM_ADDR_WIDTH-1 downto 0),
         data_a       => qnice_vram_data_out(7 downto 0),
         wren_a       => qnice_vram_we,
         q_a          => qnice_vram_data_out_i,

         clock_b      => vga_pixelclk,
         address_b    => vga_osm_vram_addr(VRAM_ADDR_WIDTH-1 downto 0),
         q_b          => vga_osm_vram_data
      ); -- osm_vram : entity work.dualport_2clk_ram

   -- Dual port & dual clock attribute RAM: contains inverse attribute, light/dark attrib. and colors of the chars
   -- bit 7: 1=inverse
   -- bit 6: 1=dark, 0=bright
   -- bit 5: background red
   -- bit 4: background green
   -- bit 3: background blue
   -- bit 2: foreground red
   -- bit 1: foreground green
   -- bit 0: foreground blue
   osm_vram_attr : entity work.dualport_2clk_ram
      generic map
      (
         ADDR_WIDTH   => VRAM_ADDR_WIDTH,
         DATA_WIDTH   => 8,
         FALLING_A    => true
      )
      port map
      (
         clock_a      => qnice_clk,
         address_a    => qnice_vram_addr(VRAM_ADDR_WIDTH-1 downto 0),
         data_a       => qnice_vram_data_out(7 downto 0),
         wren_a       => qnice_vram_attr_we,
         q_a          => qnice_vram_attr_data_out_i,

         clock_b      => vga_pixelclk,
         address_b    => vga_osm_vram_addr(VRAM_ADDR_WIDTH-1 downto 0),       -- same address as VRAM
         q_b          => vga_osm_vram_attr
      ); -- osm_vram_attr : entity work.dualport_2clk_ram

end beh;
