create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# New AE diagnostic link is an acknowledged asynchronous mailbox. The source
# payload remains held until the synchronized destination acknowledgment returns.
# These are the only functional transfers between the camera-control 24MHz and
# HDMI pixel domains; local pipelines in either clock domain remain timed.
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}]

# Hard MCU AHB divider must match BSP. Generated clocks are derived above.
set_ip_property AHB_DIV 2 [get_cells {u_voice/u_mcu/PH1P_PHY_MCU_Inst}]
# Voice crosses into the pixel domain only through held-payload mailboxes.
set_false_path -to [get_pins {u_voice/u_select/req_sync_reg[0].d}]
# I2S SD is source-synchronous to our 1 MHz SCK; receiver uses a 2-FF input.
set_false_path -from [get_ports {I_mic_sd}] -to [get_pins {u_voice/u_audio/u_rx/sd_sync_reg[0].d}]

# Only first synchronizer stages are asynchronous. Their second stages and all
# local logic remain timed. Do not declare the complete voice clocks false.
set_false_path -to [get_pins {u_voice/u_bus/req_sync_reg[0].d u_voice/u_bus/ack_sync_reg[0].d u_voice/u_audio/ack_sync_reg[0].d}]
set_false_path -to [get_pins {u_voice/u_telemetry/data_1_reg*.d u_voice/u_telemetry/req_1_reg.d u_voice/u_telemetry/ack_1_reg.d}]
# Asynchronous assertion, synchronous deassertion reset chains.
set_false_path -to [get_pins {u_voice/core_reset_pipe_reg*.sr u_voice/hreset_pipe_reg*.sr}]

# Bundled payloads are held until the return ACK. Constrain their actual data
# path delay, not a near-zero phase coincidence of independent PLL domains.
# Request payload has >=2 destination clocks before consumption (40 ns / 26 ns).
# AHB<->50MHz has only the bridge's held request/response and their toggle
# synchronizers. Packed SEQ cells can merge unrelated register names, so bind
# these finite DATA-PATH bounds to the two clock objects rather than cell names.
# This does not false-path setup: every crossing still has a finite delay check.
# All paths inside either clock domain retain their normal setup/hold checks.
set_max_delay 20.0 -datapath_only -from [get_clocks {u_voice/u_mcu/PH1P_PHY_MCU_Inst.ahb_clk}] -to [get_clocks {sys_clk_50m}]
set_false_path -hold -from [get_clocks {u_voice/u_mcu/PH1P_PHY_MCU_Inst.ahb_clk}] -to [get_clocks {sys_clk_50m}]
# Response payload settles before the ACK traverses two AHB synchronizer stages.
set_max_delay 10.0 -datapath_only -from [get_clocks {sys_clk_50m}] -to [get_clocks {u_voice/u_mcu/PH1P_PHY_MCU_Inst.ahb_clk}]
set_false_path -hold -from [get_clocks {sys_clk_50m}] -to [get_clocks {u_voice/u_mcu/PH1P_PHY_MCU_Inst.ahb_clk}]
set_max_delay 20.0 -datapath_only -from [get_cells {u_voice/u_audio/command_reg*}] -to [get_cells {u_voice/u_select/operation_reg* u_voice/u_select/color_reg* u_voice/u_select/shape_reg*}]
set_false_path -hold -from [get_cells {u_voice/u_audio/command_reg*}] -to [get_cells {u_voice/u_select/operation_reg* u_voice/u_select/color_reg* u_voice/u_select/shape_reg*}]

# Pixel -> 50MHz consists of the voice telemetry mailbox and command ACK.
# held/data_1 registers also merge names during physical packing. A 20ns
# bounded data delay is safely below the mailbox's >=2 destination-clock wait.
set_max_delay 20.0 -datapath_only -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {sys_clk_50m}]
set_false_path -hold -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {sys_clk_50m}]

# External switches are asynchronous only up to their first synchronizer.
set_false_path -from [get_ports {I_voice_keys_n*}] -to [get_cells {u_voice/u_audio/u_buttons/meta_reg*}]

# MOTION_R1 axis-state mailbox holds its payload until pixel-domain ACK.
set_max_delay 20.0 -datapath_only -from [get_clocks {sys_clk_50m}] -to [get_clocks {HDMI_PIXEL_CLK}]
set_false_path -hold -from [get_clocks {sys_clk_50m}] -to [get_clocks {HDMI_PIXEL_CLK}]
