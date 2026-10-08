#####################################################################
# syn_tensor_core.tcl - Design Compiler synthesis of tensor_core
#                       (FreePDK45 / OSU gscl45nm standard cells)
#
# Run from the tensor/ directory (tcsh, after sourcing the tool setup):
#   setenv PERIOD 2.5                  # clock period in ns (default 2.5 = 400 MHz)
#   dc_shell -f scripts/syn_tensor_core.tcl | tee dc_$PERIOD.log
#
# Reports : report/tensor_core_<PERIOD>ns.*
# Outputs : netlist/tensor_core_syn.v / .sdc / .ddc  (input to Innovus;
#           overwritten on every run)
#####################################################################

set design tensor_core
set period [expr {[info exists ::env(PERIOD)] ? $::env(PERIOD) : 2.5}]
set tag    ${design}_${period}ns
file mkdir report netlist

#--------------------------------------------------------------------
# 1. Libraries
#--------------------------------------------------------------------
set search_path       [list . /tools/PDK/NCSU45PDK/FreePDK45/osu_soc/lib/files]
set target_library    gscl45nm.db
set synthetic_library dw_foundation.sldb     ;# DesignWare multiplier/adder architectures
set link_library      [list * gscl45nm.db dw_foundation.sldb]

#--------------------------------------------------------------------
# 2. Read RTL (tensor_core only depends on mac_cell)
#    Expected warnings: register initial values (= 0) are ignored and
#    Vivado attributes such as (* keep *) are not recognized. ASIC flops
#    have no power-on value, so this is fine.
#--------------------------------------------------------------------
analyze -format verilog [list rtl/mac_cell.v rtl/tensor_core.v]
elaborate $design                ;# default ROWS=2, COLS=8 -> 16 MACs
current_design $design
link
check_design > report/${tag}.check_design

# Some gscl45nm output pins are characterized with max_capacitance = 0,
# so any load is flagged as a DRV that DC cannot fix (it just inserts
# buffers). Drop those attributes in memory only (library file untouched)
# and rely on max_transition as the electrical check.
set bad_pins [get_lib_pins -quiet gscl45nm/*/* -filter "max_capacitance == 0"]
echo "Info: removing max_capacitance = 0 from [sizeof_collection $bad_pins] library pins"
if {[sizeof_collection $bad_pins] > 0} { remove_attribute $bad_pins max_capacitance }

#--------------------------------------------------------------------
# 3. Constraints
#--------------------------------------------------------------------
create_clock -name clk -period $period [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]          ;# jitter + skew margin before CTS

set in_ports [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  [expr {0.2 * $period}] -clock clk $in_ports
set_output_delay [expr {0.2 * $period}] -clock clk [all_outputs]
set_driving_cell -lib_cell INVX4 $in_ports          ;# inputs driven by an INVX4
set_load 0.01 [all_outputs]                         ;# 10 fF (library cap unit is pF)

check_timing > report/${tag}.check_timing

#--------------------------------------------------------------------
# 4. Compile (-no_autoungroup keeps the mac_cell hierarchy so per-MAC
#    area stays visible)
#--------------------------------------------------------------------
# Clean netlist for P&R: no assign statements (port-to-port / constant nets)
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
compile_ultra -no_autoungroup

#--------------------------------------------------------------------
# 5. Reports
#--------------------------------------------------------------------
report_qor                         > report/${tag}.qor
report_timing -max_paths 5         > report/${tag}.timing
report_area -hierarchy             > report/${tag}.area
report_power                       > report/${tag}.power
report_reference -hierarchy        > report/${tag}.ref
report_constraint -all_violators   > report/${tag}.violators

#--------------------------------------------------------------------
# 6. Outputs for Innovus
#--------------------------------------------------------------------
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output netlist/${design}_syn.v
write_sdc                               netlist/${design}_syn.sdc
write -format ddc -hierarchy     -output netlist/${design}.ddc

exit
