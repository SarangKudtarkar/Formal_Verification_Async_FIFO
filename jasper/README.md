# JasperGold FPV testbench — async_fifo

Formal environment for `../async_fifo.sv` (unmodified RTL).

```text
jasper/
├── async_fifo_fpv_top.sv   wrapper: DUT + props, free inputs (clocks, rst, wr_data, sym_*)
├── async_fifo_props.sv     assumptions, assertions, covers, reference model
├── async_fifo_fpv.tcl      JasperGold flow
└── model_check.py          Python random-clock model of the RTL (pre-JG sanity / mutation check)
```

## Run

```bash
cd jasper
jaspergold -tcl async_fifo_fpv.tcl
```

Override size in the `elaborate` line, e.g. `-parameter DEPTH 16 -parameter DATAWIDTH 4`.

## Clocking

`wr_clk` and `rd_clk` are declared as two separate `clock`s with no relationship, so JasperGold explores
every interleaving of edges. This is different from the existing `async_fifo.sby` flow, which runs without
`multiclock on` and effectively ticks both domains in lockstep.

Consequence: `!(full && empty)` is **not** a valid property under independent clocks. After a full FIFO
is drained, `full` stays high until the read pointer crosses the 2-FF synchronizer, while `empty` is
already high. The cover `c_full_and_empty` is expected to be reachable. Instead of that property, the
environment checks that the flags are *sound* against the true occupancy.

## What is checked

| Group | Properties |
|-------|------------|
| Reset | `rst -> empty && rd_data==0`, `rst -> !full` |
| Safety | `no_overflow_underflow` (true occupancy <= DEPTH), `full_sound`, `empty_sound` |
| Pointers | binary pointers match reference counters, Gray encoding, 1-bit Gray change per edge |
| CDC lemmas | `sync_view_split`, `stale_occ_bound` (synchronized pointers only lag, never lead) |
| Data | `a_data_integrity`: symbolic scoreboard (free `sym_idx`/`sym_data`) proves ordering, no loss, no duplication, no corruption |
| Covers | full, drain after full, pointer wrap, full&&empty, tracked item written and read |

Assumptions: reset applied once at power-on and never re-asserted; `sym_*` stable; the write whose sequence
number equals `sym_idx` carries `sym_data`; `wr_data` otherwise free.

Not covered yet: mid-run reset, independent reset release per domain, liveness (full eventually clears),
CDC structural checks (use a CDC app for those).

## Pre-JG sanity check (no JasperGold needed)

```bash
python3 model_check.py
```

Simulates the RTL under random independent clocks (six rate ratios), checks the same invariants, and runs
injected-bug mutants. Expected: no failures on the clean RTL; assertion failures for the mutants
`write_when_full`, `rd_offbyone`, `empty_late`, `gray_bug`, `full_noinv`. The `full_early` mutant (capacity
loss) is only caught by covers (`c_occ_full` / `c_fill_then_drain` unreachable).

The JasperGold flow itself has not been run in the environment where this was written (no JG licence);
the SVA was checked for syntax/elaboration with slang and the invariants against the Python model.
