# ============================================================================
# async_fifo_fpv.tcl - JasperGold FPV setup for async_fifo
#
# Run from the jasper/ directory:
#     jaspergold -allow_unsupported_OS -tcl async_fifo_fpv.tcl      (batch / GUI)
#     jg -no_gui async_fifo_fpv.tcl                                 (older name)
#
# (Written against the standard JasperGold FPV Tcl flow; adjust option names
#  if your JG version differs.)
# ============================================================================
clear -all

# --- Sources -----------------------------------------------------------------
analyze -sv12 ../async_fifo.sv
analyze -sv12 async_fifo_props.sv
analyze -sv12 async_fifo_fpv_top.sv

# --- Elaborate ---------------------------------------------------------------
# Override defaults with e.g.:  -parameter DEPTH 16 -parameter DATAWIDTH 4
elaborate -top async_fifo_fpv_top

# --- Clocks ------------------------------------------------------------------
# Two separate clock declarations with no -factor/-phase relationship =>
# independent (asynchronous) clocks: any interleaving of edges is explored.
clock wr_clk
clock rd_clk

# --- Reset -------------------------------------------------------------------
# Single async active-high reset applied at power-on; the props module also
# assumes it is never re-asserted.
reset -expression {rst}

# --- Sanity before proving ---------------------------------------------------
check_assumptions -conflict        ;# environment must not be over-constrained
# (covers are proven by the prove -all below; unreachable covers = vacuity red flag)

# --- Prove -------------------------------------------------------------------
set_prove_time_limit 1h
prove -all

# --- Report ------------------------------------------------------------------
report
