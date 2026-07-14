###################################################################

# Created by write_sdc on Sat Jan 11 15:23:27 2025

###################################################################
set sdc_version 2.1

set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA
set_wire_load_model -name TSMC128K_Conservative -library tcb018gbwp7ttc
set_load -pin_load 0.01 [get_ports {Count[2]}]
set_load -pin_load 0.01 [get_ports {Count[1]}]
set_load -pin_load 0.01 [get_ports {Count[0]}]
create_clock [get_ports clk]  -period 4  -waveform {2 4}
set_max_delay 0  -from [list [get_ports {Data_in[2]}] [get_ports {Data_in[1]}] [get_ports      \
{Data_in[0]}] [get_ports load] [get_ports count_up] [get_ports counter_on]     \
[get_ports clk] [get_ports rst]]  -to [list [get_ports {Count[2]}] [get_ports {Count[1]}] [get_ports {Count[0]}]]
set_input_delay -clock clk  0.2  [get_ports clk]
set_input_delay -clock clk  0.2  [get_ports {Data_in[2]}]
set_input_delay -clock clk  0.2  [get_ports {Data_in[1]}]
set_input_delay -clock clk  0.2  [get_ports {Data_in[0]}]
set_input_delay -clock clk  0.2  [get_ports load]
set_input_delay -clock clk  0.2  [get_ports count_up]
set_input_delay -clock clk  0.2  [get_ports counter_on]
set_input_delay -clock clk  0.2  [get_ports rst]
set_output_delay -clock clk  0.2  [get_ports {Count[2]}]
set_output_delay -clock clk  0.2  [get_ports {Count[1]}]
set_output_delay -clock clk  0.2  [get_ports {Count[0]}]
set_drive 0.01  [get_ports {Data_in[2]}]
set_drive 0.01  [get_ports {Data_in[1]}]
set_drive 0.01  [get_ports {Data_in[0]}]
set_drive 0.01  [get_ports load]
set_drive 0.01  [get_ports count_up]
set_drive 0.01  [get_ports counter_on]
set_drive 0.01  [get_ports clk]
set_drive 0.01  [get_ports rst]
