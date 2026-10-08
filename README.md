# ASIC Design Flow

RTL-to-GDS implementations of blocks from my research design, a scaled-down NVIDIA-style GPU first built on a Virtex-7 FPGA. Each block goes through logic synthesis (Synopsys Design Compiler), place-and-route (Cadence Innovus) and sign-off timing in the FreePDK45 / OSU 45 nm standard-cell library.

| Block | Status | Highlights |
|---|---|---|
| [`tensor/`](tensor/) — tensor-core sub-partition (16 int16 MACs) | Signed off | 400 MHz post-route (setup +45 ps, hold +229 ps, OCV), 0 DRC, 0.14 mm² die; synthesis sweep to 1.25 GHz |
| `sm/` — full SM (4 tensor cores, operand buffers, 2 clock domains) | Planned | Multi-clock SDC and CDC constraints |

![tensor_core layout](tensor/images/tensor_core_layout.gif)

**Tools:** Synopsys Design Compiler · Cadence Innovus · Tcl · Verilog
**Library:** FreePDK45, OSU `gscl45nm` standard cells
