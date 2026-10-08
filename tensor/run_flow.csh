#!/bin/tcsh -f
#####################################################################
# run_flow.csh - full tensor_core flow: DC synthesis -> Innovus P&R ->
#                extra post-route optimization -> sign-off timing.
#
# Run from the tensor/ directory:  ./run_flow.csh
#
# Site-specific: the setup files below are the ones used on the USC
# Viterbi servers. Design Compiler and Innovus were licensed through
# different setup files, so each tool runs in its own sub-shell.
#####################################################################

set SYN_SETUP = ~/setup_v1721.csh          # environment for Design Compiler
set PNR_SETUP = ~/setup_ee577b_v26.csh     # environment for Innovus 25.1
if (! $?PERIOD) setenv PERIOD 2.5          # clock period in ns (2.5 = 400 MHz)

mkdir -p report netlist pnr/tensor_core

echo "==> [1/4] Design Compiler (PERIOD = $PERIOD ns)"
tcsh -f -c "source $SYN_SETUP; dc_shell -f scripts/syn_tensor_core.tcl > dc_$PERIOD.log"
if ($status != 0) then
  echo "Synthesis failed, see dc_$PERIOD.log"; exit 1
endif

echo "==> [2/4] Innovus: floorplan -> place -> CTS -> route -> reports"
tcsh -f -c "source $PNR_SETUP; innovus -no_gui -overwrite -log pnr/tensor_core/innovus -files scripts/pnr_tensor_core.tcl"

echo "==> [3/4] Innovus: extra post-route optimization pass"
tcsh -f -c "source $PNR_SETUP; innovus -no_gui -overwrite -log pnr/tensor_core/innovus_fix -files scripts/pnr_fix_setup.tcl"

echo "==> [4/4] Innovus: sign-off timing"
tcsh -f -c "source $PNR_SETUP; innovus -no_gui -overwrite -log pnr/tensor_core/innovus_signoff -files scripts/pnr_signoff.tcl"

echo "==> Done. Sign-off timing:"
zcat pnr/tensor_core/rpt/4_signoff/*.summary.gz | grep -E "Setup mode|Hold mode|WNS|Violating"
tail -1 pnr/tensor_core/rpt/drc.rpt
