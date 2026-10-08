#####################################################################
# pnr_signoff.tcl - Sign-off timing with post-CTS clock uncertainty
#                   reduced from 0.10 ns to 0.05 ns.
#
# Why: before CTS the clock is ideal (zero skew), so the 0.10 ns
# uncertainty covers jitter (~0.05 ns) plus estimated skew (~0.05 ns).
# After CTS the clock is propagated and the real skew (0.133 ns here) is
# already in every path, so keeping 0.10 ns would count skew twice.
# Post-CTS, only the jitter component (0.05 ns) is kept.
#
# Run from the tensor/ directory:
#   innovus -no_gui -overwrite -log pnr/tensor_core/innovus_signoff -files scripts/pnr_signoff.tcl
#####################################################################

set design tensor_core
set out    pnr/$design

proc step {name body} {
  puts "\n==================== STEP: $name ===================="
  if {[catch {uplevel 1 $body} err]} {
    puts "STEP-FAIL: $name : $err"
    return 0
  }
  puts "STEP-OK: $name"
  return 1
}

restoreDesign $out/05_final.enc.dat $design
setMultiCpuUsage -localCpu 8

setExtractRCMode -engine postRoute
setAnalysisMode -analysisType onChipVariation -cppr both

# Record timing with the original 0.10 ns first (matches 3_postRoute)
step "timeDesign uncertainty 0.10" { timeDesign -postRoute -outDir $out/rpt/4_signoff_unc0.10 }

set_interactive_constraint_modes [all_constraint_modes -active]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]
set_interactive_constraint_modes {}

step "timeDesign setup (unc 0.05)" { timeDesign -postRoute       -outDir $out/rpt/4_signoff }
step "timeDesign hold  (unc 0.05)" { timeDesign -postRoute -hold -outDir $out/rpt/4_signoff }
step "write post-CTS SDC"          { write_sdc $out/${design}_postcts.sdc }

saveDesign $out/06_signoff.enc
puts "\n==================== SIGNOFF DONE ===================="
exit
