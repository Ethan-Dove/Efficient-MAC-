set target_library "tcb018g3d3tc_ccs.db"
set link_library "* tcb018g3d3tc_ccs.db"
set search_path ". /dfs/app/tsmc_icdc/tsmc180/tsmc180_MS_RF_G/SC/tcb018g3d3/Rev280a/Front_End/timing_power_noise/CCS/tcb018g3d3_280a"

file mkdir ../net
file mkdir ../ddc
file mkdir ../rpt

gui_start
analyze -format verilog {../rtl/efficient_mac.v}
elaborate efficient_mac -architecture verilog -library WORK
link
uplevel #0 check_design
write -hierarchy -format ddc -output ../ddc/efficient_mac_Linked.ddc
change_selection [all_inputs]
set_drive [expr 0.01] [all_inputs]
change_selection [all_outputs]
set_load [expr 0.01] [all_outputs]
create_clock clk -period 4 -waveform {2 4}
change_selection [all_inputs]
set_input_delay -clock clk -add_delay  -max -rise 0.2 [all_inputs]
set_input_delay -clock clk -add_delay -max -fall 0.2 [all_inputs]
set_input_delay -clock clk -add_delay -min -rise 0.2 [all_inputs]
set_input_delay -clock clk -add_delay  -min -fall 0.2 [all_inputs]
change_selection [all_outputs]
set_output_delay -clock clk -add_delay  -max -rise 0.2 [all_outputs]
set_output_delay -clock clk -add_delay -max -fall 0.2 [all_outputs]
set_output_delay -clock clk -add_delay -min -rise 0.2 [all_outputs]
set_output_delay -clock clk -add_delay  -min -fall 0.2 [all_outputs]
set_wire_load_model -name TSMC128K_Conservative -library tcb018gbwp7ttc_ccs
set_max_delay 0 -from [all_inputs] -to [all_outputs]
write -hierarchy -format ddc -output ../ddc/efficient_mac_Linked.ddc
compile -exact_map
write -hierarchy -format ddc -output ../ddc/efficient_mac_Synthesized.ddc
change_selection -name global -replace [get_timing_paths -delay_type max -nworst 1 -max_paths 1 -include_hierarchical_pins]
report_timing > ../rpt/timing_syn.rpt
report_area > ../rpt/area_syn.rpt
report_power > ../rpt/power_syn.rpt
change_names -rule verilog -hierarchy
write -format verilog -hierarchy -output ../net/efficient_mac_Syn.v
write_sdf ../net/efficient_mac.sdf
write_sdc ../net/efficient_mac.sdc
