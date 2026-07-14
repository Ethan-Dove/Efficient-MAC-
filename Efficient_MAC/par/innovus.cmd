#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Fri Apr  3 00:17:19 2026                
#                                                     
#######################################################

#@(#)CDS: Innovus v21.13-s100_1 (64bit) 03/04/2022 14:32 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: NanoRoute 21.13-s100_1 NR220220-0140/21_13-UB (database version 18.20.572) {superthreading v2.17}
#@(#)CDS: AAE 21.13-s034 (64bit) 03/04/2022 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: CTE 21.13-s042_1 () Mar  4 2022 08:38:36 ( )
#@(#)CDS: SYNTECH 21.13-s014_1 () Feb 17 2022 23:50:03 ( )
#@(#)CDS: CPE v21.13-s074
#@(#)CDS: IQuantus/TQuantus 20.1.2-s656 (64bit) Tue Nov 9 23:11:16 PST 2021 (Linux 2.6.32-431.11.2.el6.x86_64)

set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
win
set init_top_cell efficient_mac
set init_io_file ./efficient_mac.io
set init_verilog ../net/efficient_mac_Syn.v
set init_mmmc_file ./mmmc.view
set init_lef_file /dfs/app/tsmc_icdc/tsmc180/tsmc180_MS_RF_G/SC/tcb018g3d3/Rev280a/Back_End/lef/tcb018g3d3_280a/lef/tcb018g3d3_6lm.lef
set init_pwr_net VDD
set init_gnd_net VSS
init_design
floorPlan -site core7T -r 0.8 0.7 10 10 10 10
loadIoFile efficient_mac.io
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -instanceBasename *
globalNetConnect VSS -type pgpin -pin VSS -instanceBasename *
globalNetConnect VDD -type tiehi -instanceBasename *
globalNetConnect VSS -type tielo -instanceBasename *
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top METAL1 bottom METAL1 left METAL2 right METAL2} -width {top 1 bottom 1 left 1 right 1} -spacing {top 1 bottom 1 left 1 right 1} -offset {top 1.8 bottom 1.8 left 1.8 right 1.8} -center 1 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None
setSrouteMode -viaConnectToShape { noshape }
sroute -connect { blockPin padPin padRing corePin floatingStripe } -layerChangeRange { METAL1(1) METAL6(6) } -blockPinTarget { nearestTarget } -padPinPortConnect { allPort oneGeom } -padPinTarget { nearestTarget } -corePinTarget { firstAfterRowEnd } -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } -allowJogging 1 -crossoverViaLayerRange { METAL1(1) METAL6(6) } -nets { VDD VSS } -allowLayerChange 1 -blockPin useLef -targetViaLayerRange { METAL1(1) METAL6(6) }
setPlaceMode -fp false
place_design
win

# ---- Post-Placement Optimization ----
setOptMode -fixDRC false -fixFanoutLoad true
optDesign -preCTS

# ---- Clock Tree Synthesis ----
ccopt_design -cts
optDesign -postCTS

# ---- Route Design ----
setNanoRouteMode -routeWithSiDriven true
routeDesign

# ---- Post-Route Optimization ----
optDesign -postRoute
optDesign -postRoute -hold

# ---- Timing Signoff ----
setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute -pathReports -drvReports -slackReports -numPaths 50 \
    -prefix efficient_mac_postRoute -outDir ../rpt
timeDesign -postRoute -hold -pathReports -slackReports -numPaths 50 \
    -prefix efficient_mac_postRoute_hold -outDir ../rpt

# ---- Filler Cells ----
addFiller -cell FILL8 FILL4 FILL2 FILL1 -prefix FILL

# ---- Verify ----
verifyConnectivity -type all -error 1000 -warning 50
verify_drc -limit 1000

# ---- Export GDS ----
streamOut ../par/efficient_mac.gds \
    -mapFile ./scripts/streamOut.map \
    -libName DesignLib \
    -units 1000 \
    -mode ALL

# ---- Save Netlist and SDF for par_sim ----
saveNetlist ../par/efficient_mac.v
write_sdf -setuphold split -edge noedge ../par/efficient_mac.sdf

# ---- Save Design Database ----
saveDesign ./efficient_mac.enc
