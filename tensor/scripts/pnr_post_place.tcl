#####################################################################
# pnr_post_place.tcl - Innovus 25.1 P&R, part 2: CTS -> route ->
#                      post-route optimization -> checks -> outputs
#
# Two ways to run it:
#   (a) sourced by pnr_tensor_core.tcl after placement (full run)
#   (b) on its own, restarting from the 02_place.enc checkpoint:
#         innovus -no_gui -overwrite -log pnr/tensor_core/innovus_post -files scripts/pnr_post_place.tcl
#
# Every step is wrapped in `step`: a failure prints
# "STEP-FAIL: <step> : <reason>" and non-critical steps keep going.
#####################################################################

set design [expr {[info exists ::env(DESIGN)] ? $::env(DESIGN) : "tensor_core"}]
set out    pnr/$design
set pdk    /tools/PDK/NCSU45PDK/FreePDK45/osu_soc/lib/files
file mkdir $out/rpt

if {![info exists ::pnr_in_session]} {
  restoreDesign $out/02_place.enc.dat $design
  setMultiCpuUsage -localCpu 8
}

proc step {name body} {
  puts "\n==================== STEP: $name ===================="
  if {[catch {uplevel 1 $body} err]} {
    puts "STEP-FAIL: $name : $err"
    return 0
  }
  puts "STEP-OK: $name"
  return 1
}

#--------------------------------------------------------------------
# 5. CTS
#    In Innovus 25.1, place_opt_design produces a PODv2 database, which
#    the legacy ccopt_design rejects (IMPCCOPT-2440). clock_opt_design
#    builds the clock tree and runs post-CTS optimization in one step.
#    gscl45nm has no dedicated clock inverters: use CLKBUF1/2/3 + INVX*.
#--------------------------------------------------------------------
set_ccopt_property buffer_cells   {CLKBUF1 CLKBUF2 CLKBUF3}
set_ccopt_property inverter_cells {INVX1 INVX2 INVX4 INVX8}
step "create_ccopt_clock_tree_spec" { create_ccopt_clock_tree_spec }
if {![step "clock_opt_design" { clock_opt_design }]} { exit 1 }

step "hold fix (postCTS)"      { optDesign -postCTS -hold }
step "timeDesign postCTS"      { timeDesign -postCTS       -outDir $out/rpt/2_postCTS }
step "timeDesign postCTS hold" { timeDesign -postCTS -hold -outDir $out/rpt/2_postCTS }
step "report CTS skew"         { report_ccopt_skew_groups -file $out/rpt/cts_skew.rpt }
step "report CTS trees"        { report_ccopt_clock_trees -file $out/rpt/cts_trees.rpt }
saveDesign $out/03_cts.enc

#--------------------------------------------------------------------
# 6. Route + post-route optimization
#--------------------------------------------------------------------
setNanoRouteMode -routeWithTimingDriven true -drouteFixAntenna true
if {![step "routeDesign" { routeDesign -globalDetail }]} {
  # Fall back to the newer combined command if the PODv2 database
  # rejects the legacy router call
  if {![step "route_opt_design" { route_opt_design }]} { exit 1 }
}

setExtractRCMode -engine postRoute
# Post-route timing requires OCV analysis mode (otherwise IMPOPT-7027)
setAnalysisMode -analysisType onChipVariation -cppr both

step "optDesign postRoute"      { optDesign -postRoute }
step "optDesign postRoute hold" { optDesign -postRoute -hold }
saveDesign $out/04_route.enc

#--------------------------------------------------------------------
# 7. Filler + checks + reports
#--------------------------------------------------------------------
step "addFiller"                 { addFiller -cell FILL -prefix FILLER }
step "timeDesign postRoute"      { timeDesign -postRoute       -outDir $out/rpt/3_postRoute }
step "timeDesign postRoute hold" { timeDesign -postRoute -hold -outDir $out/rpt/3_postRoute }
step "verify_drc"                { verify_drc -report $out/rpt/drc.rpt }
step "verifyConnectivity"        { verifyConnectivity -type all -report $out/rpt/connectivity.rpt }
step "report_power"              { report_power -outfile $out/rpt/power.rpt }
step "summaryReport"             { summaryReport -noHtml -outfile $out/rpt/summary.rpt }

#--------------------------------------------------------------------
# 8. Outputs: SPEF for STA, netlist/SDF for gate-level sim, GDS
#--------------------------------------------------------------------
step "extractRC"   { extractRC }
step "SPEF"        { rcOut -spef $out/${design}.spef -rc_corner rc_typ }
step "netlist"     { saveNetlist $out/${design}_pnr.v }
step "SDF"         { write_sdf $out/${design}_pnr.sdf }
step "GDS"         { streamOut $out/${design}.gds -mapFile $pdk/gds2_encounter.map -units 2000 -mode ALL }
saveDesign $out/05_final.enc

puts "\n==================== P&R DONE ===================="
exit
