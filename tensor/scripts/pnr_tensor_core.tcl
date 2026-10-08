#####################################################################
# pnr_tensor_core.tcl - Innovus 25.1 P&R, part 1: import -> floorplan
#                       -> power plan -> placement. Hands off to
#                       pnr_post_place.tcl for CTS -> route -> sign-off.
#
# Run from the tensor/ directory (tcsh, after sourcing the tool setup):
#   mkdir -p pnr/tensor_core
#   innovus -no_gui -overwrite -log pnr/tensor_core/innovus -files scripts/pnr_tensor_core.tcl
#
# Inputs : netlist/tensor_core_syn.v, netlist/tensor_core_syn.sdc (from DC)
#          FreePDK45 OSU library under /tools/PDK/.../osu_soc/lib/files
# Outputs: pnr/tensor_core/  (reports in rpt/, one *.enc checkpoint per stage)
#####################################################################

set design [expr {[info exists ::env(DESIGN)] ? $::env(DESIGN) : "tensor_core"}]
set util   0.60      ;# target core utilization
set out    pnr/$design
set pdk    /tools/PDK/NCSU45PDK/FreePDK45/osu_soc/lib/files
file mkdir $out/rpt $out/lib

#--------------------------------------------------------------------
# 0. Local copy of the .lib without the "max_capacitance : 0" lines
#    (same library defect as in DC; the original file is untouched)
#--------------------------------------------------------------------
set fin  [open $pdk/gscl45nm.lib r]
set fout [open $out/lib/gscl45nm_fixcap.lib w]
set ndrop 0
while {[gets $fin line] >= 0} {
  if {[regexp {^\s*max_capacitance\s*:\s*0\s*;} $line]} { incr ndrop; continue }
  puts $fout $line
}
close $fin
close $fout
puts "Info: dropped $ndrop 'max_capacitance : 0' lines from gscl45nm.lib"

setMultiCpuUsage -localCpu 8

#--------------------------------------------------------------------
# 1. MMMC: one typical corner, SDC taken directly from DC
#--------------------------------------------------------------------
set fh [open $out/mmmc.view w]
puts $fh "create_library_set     -name ls_typ -timing {$out/lib/gscl45nm_fixcap.lib}"
puts $fh "create_rc_corner       -name rc_typ"
puts $fh "create_delay_corner    -name dc_typ -library_set ls_typ -rc_corner rc_typ"
puts $fh "create_constraint_mode -name cm_func -sdc_files {netlist/${design}_syn.sdc}"
puts $fh "create_analysis_view   -name av_typ -constraint_mode cm_func -delay_corner dc_typ"
puts $fh "set_analysis_view -setup {av_typ} -hold {av_typ}"
close $fh

#--------------------------------------------------------------------
# 2. Import
#--------------------------------------------------------------------
set init_lef_file  $pdk/gscl45nm.lef
set init_verilog   netlist/${design}_syn.v
set init_top_cell  $design
set init_mmmc_file $out/mmmc.view
set init_pwr_net   vdd
set init_gnd_net   gnd
init_design
setDesignMode -process 45

#--------------------------------------------------------------------
# 3. Floorplan + power plan
#--------------------------------------------------------------------
# Aspect ratio 1.0, utilization $util, 10 um core-to-die margin for the ring
floorPlan -site CoreSite -r 1.0 $util 10 10 10 10

globalNetConnect vdd -type pgpin -pin vdd -inst * -override
globalNetConnect gnd -type pgpin -pin gnd -inst * -override
globalNetConnect vdd -type tiehi -inst *
globalNetConnect gnd -type tielo -inst *

addRing -nets {vdd gnd} -type core_rings -follow core \
    -layer   {top metal9 bottom metal9 left metal10 right metal10} \
    -width   {top 2 bottom 2 left 2 right 2} \
    -spacing {top 1 bottom 1 left 1 right 1} \
    -offset  {top 2 bottom 2 left 2 right 2}
# Ring offset raised from 1 um to 2 um: at 1 um the stripe vias at the core
# edge sat 0.6 um from the metal9 ring (rule: 0.8 um) -> 20 spacing DRCs.

addStripe -nets {vdd gnd} -layer metal10 -direction vertical \
    -width 1 -spacing 1 -set_to_set_distance 40 \
    -start_from left -start_offset 15

# Connect every row's metal1 follow-pin rails to the ring / stripes
sroute -connect {corePin} -nets {vdd gnd} \
    -layerChangeRange {metal1 metal10} \
    -targetViaLayerRange {metal1 metal10} \
    -crossoverViaLayerRange {metal1 metal10} \
    -allowLayerChange 1 -allowJogging 1

saveDesign $out/01_floorplan.enc

#--------------------------------------------------------------------
# 4. Placement + pre-CTS optimization
#--------------------------------------------------------------------
setPlaceMode -timingDriven true -placeIOPins true
place_opt_design
timeDesign -preCTS -outDir $out/rpt/1_preCTS
saveDesign $out/02_place.enc

#--------------------------------------------------------------------
# 5-8. CTS and later stages live in pnr_post_place.tcl, which can also
#      be run on its own starting from 02_place.enc
#--------------------------------------------------------------------
set ::pnr_in_session 1
set here [file dirname [info script]]
if {![file exists [file join $here pnr_post_place.tcl]]} { set here . }
source [file join $here pnr_post_place.tcl]
