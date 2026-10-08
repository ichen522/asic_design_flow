#####################################################################
# pnr_fix_setup.tcl - Restart from 04_route.enc, run one more high-effort
#                     post-route setup optimization pass, then redo
#                     filler, checks, reports and outputs (overwrites
#                     05_final).
#
# Run from the tensor/ directory:
#   innovus -no_gui -overwrite -log pnr/tensor_core/innovus_fix -files scripts/pnr_fix_setup.tcl
#####################################################################

set design tensor_core
set out    pnr/$design
set pdk    /tools/PDK/NCSU45PDK/FreePDK45/osu_soc/lib/files

proc step {name body} {
  puts "\n==================== STEP: $name ===================="
  if {[catch {uplevel 1 $body} err]} {
    puts "STEP-FAIL: $name : $err"
    return 0
  }
  puts "STEP-OK: $name"
  return 1
}

restoreDesign $out/04_route.enc.dat $design
setMultiCpuUsage -localCpu 8

setExtractRCMode -engine postRoute
setAnalysisMode -analysisType onChipVariation -cppr both

# Record the state before the extra pass
step "timeDesign before" { timeDesign -postRoute -outDir $out/rpt/3a_before_fix }

#--------------------------------------------------------------------
# Extra post-route optimization (high effort + incremental), then hold
#--------------------------------------------------------------------
step "setOptMode high effort"   { setOptMode -effort high }
step "optDesign postRoute"      { optDesign -postRoute }
step "optDesign postRoute incr" { optDesign -postRoute -incr }
step "optDesign postRoute hold" { optDesign -postRoute -hold }
saveDesign $out/04b_route_opt.enc

#--------------------------------------------------------------------
# Filler + checks + reports (same as steps 7 and 8 of pnr_post_place.tcl)
#--------------------------------------------------------------------
step "addFiller"                 { addFiller -cell FILL -prefix FILLER }
step "timeDesign postRoute"      { timeDesign -postRoute       -outDir $out/rpt/3_postRoute }
step "timeDesign postRoute hold" { timeDesign -postRoute -hold -outDir $out/rpt/3_postRoute }
step "verify_drc"                { verify_drc -report $out/rpt/drc.rpt }
step "verifyConnectivity"        { verifyConnectivity -type all -report $out/rpt/connectivity.rpt }
step "report_power"              { report_power -outfile $out/rpt/power.rpt }
step "summaryReport"             { summaryReport -noHtml -outfile $out/rpt/summary.rpt }

step "extractRC" { extractRC }
step "SPEF"      { rcOut -spef $out/${design}.spef -rc_corner rc_typ }
step "netlist"   { saveNetlist $out/${design}_pnr.v }
step "SDF"       { write_sdf $out/${design}_pnr.sdf }
step "GDS"       { streamOut $out/${design}.gds -mapFile $pdk/gds2_encounter.map -units 2000 -mode ALL }
saveDesign $out/05_final.enc

puts "\n==================== FIX DONE ===================="
exit
