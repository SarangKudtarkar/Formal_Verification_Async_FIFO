# Asynchronous FIFO — SystemVerilog + Formal Verification

This project implements and verifies a simple asynchronous FIFO using SystemVerilog.
The verification flow uses **Yosys, SymbiYosys, and Z3** for formal verification, and **Verilator + GTKWave** for simulation and waveform inspection.

---

## Quick Start

Run lint, simulation, and formal verification in one go:

```bash
verilator --lint-only --timing async_fifo.sv async_tb.sv --top-module async_tb && \
verilator --binary --timing --trace async_fifo.sv async_tb.sv --top-module async_tb && \
./obj_dir/Vasync_tb && \
rm -rf async_fifo && \
sby -f async_fifo.sby
```

This chain will:

1. Lint the RTL and testbench (`--lint-only`).
2. Build the simulation binary with waveform tracing (`--trace`).
3. Run the simulation, generating `async_fifo.vcd`.
4. Clear any previous formal proof output directory.
5. Run the formal proof with SymbiYosys.

---

## 1. Project Structure

```text
Formal_Verification_Async_FIFO/
├── async_fifo.sv
├── async_fifo_formal.sv
├── async_fifo.sby
├── async_tb.sv
├── README.md
└── .gitignore
```

### Files

- `async_fifo.sv` — asynchronous FIFO RTL.
- `async_fifo_formal.sv` — formal verification harness containing assertions and cover properties.
- `async_fifo.sby` — SymbiYosys configuration.
- `async_tb.sv` — simulation testbench.
- `README.md` — project documentation.

---

## 2. FIFO Architecture

The FIFO uses two independent clock domains:

- Write clock: `wr_clk`
- Read clock: `rd_clk`

Each domain maintains its own pointer.

```text
             WRITE DOMAIN
        ┌─────────────────────┐
        │ wr_clk              │
        │                     │
wr_data ──> Memory            │
        │     ↑               │
        │ write pointer       │
        └─────┬───────────────┘
              │
              │ Gray-coded pointer
              │
           2-FF synchronizer
              │
              ▼
        ┌─────────────────────┐
        │ READ DOMAIN         │
        │                     │
        │ read pointer        │
        │        ↓            │
        │      Memory         │
        │        ↓            │
        │     rd_data         │
        └─────────────────────┘
```

The write pointer is synchronized into the read-clock domain, and the read pointer is synchronized into the write-clock domain.

---

## 3. Why Gray Code Is Used

Binary counters can change several bits at the same time.

For example:

```text
Binary: 0111 -> 1000
```

Four bits change.

If a multi-bit binary pointer crosses clock domains directly, the receiving clock domain could temporarily observe an invalid combination of bits.

Gray code changes only one bit between adjacent values.

Binary-to-Gray conversion:

```systemverilog
gray = (binary >> 1) ^ binary;
```

Example:

| Binary | Gray |
|--------|------|
| 0000   | 0000 |
| 0001   | 0001 |
| 0010   | 0011 |
| 0011   | 0010 |
| 0100   | 0110 |

This makes Gray-coded pointers suitable for asynchronous FIFO clock-domain crossing.

---

## 4. Clock-Domain Crossing

The FIFO uses two flip-flop stages to synchronize the Gray-coded pointer into the other clock domain.

**Read pointer into write domain:**

```systemverilog
always_ff @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst) begin
        rd_ptr_gray_sync1 <= '0;
        rd_ptr_gray_sync2 <= '0;
    end
    else begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
end
```

**Write pointer into read domain:**

```systemverilog
always_ff @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst) begin
        wr_ptr_gray_sync1 <= '0;
        wr_ptr_gray_sync2 <= '0;
    end
    else begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
end
```

The second stage is used by the receiving logic.

---

## 5. Full and Empty Detection

### Empty

The FIFO is empty when the current read pointer is equal to the synchronized write pointer.

The RTL calculates the next read pointer and compares it with the synchronized write pointer:

```systemverilog
empty <= (rd_ptr_gray_next == wr_ptr_gray_sync2);
```

### Full

For a power-of-two FIFO, the full condition is detected by comparing the next write Gray pointer with the synchronized read pointer after inverting the upper pointer bits.

Conceptually:

```text
write pointer == read pointer
        ↓
same address
        ↓
extra pointer bits distinguish
empty vs full
```

An additional pointer bit is therefore used beyond the memory address bits.

---

## 6. Pointer Width

For:

```text
DEPTH = 8
```

the address requires:

```text
$clog2(8) = 3 bits
```

The pointer uses one additional bit:

```text
PTR_WIDTH + 1
```

The lower address bits select the memory location, while the additional bit(s) help distinguish a full FIFO from an empty FIFO.

---

## 7. Simulation

The simulation uses:

- Verilator
- VCD waveform tracing
- GTKWave

### Compile and run

```bash
verilator --binary --timing --trace async_fifo.sv async_tb.sv --top-module async_tb
```

Run:

```bash
./obj_dir/Vasync_tb
```

This generates:

```text
async_fifo.vcd
```

Open the waveform:

```bash
gtkwave async_fifo.vcd
```

Useful signals to inspect:

- `wr_clk`
- `rd_clk`
- `wr_rst`
- `rd_rst`
- `wr_data`
- `rd_data`
- `full`
- `empty`

---

## 8. Formal Verification

The formal verification flow uses:

```text
SystemVerilog
      ↓
   Yosys
      ↓
SymbiYosys (SBY)
      ↓
     Z3
```

The SBY configuration is:

```ini
[options]
mode prove
depth 20

[engines]
smtbmc z3

[script]
read_verilog -formal -sv async_fifo.sv
read_verilog -formal -sv async_fifo_formal.sv
prep -top async_fifo_formal

[files]
async_fifo.sv
async_fifo_formal.sv
```

---

## 9. Running the Formal Proof

First remove the previous SBY output directory:

```bash
rm -rf async_fifo
```

Then run:

```bash
sby -f async_fifo.sby
```

A successful proof should contain results similar to:

```text
engine_0.basecase: Status returned by engine for basecase: pass
engine_0.induction: Temporal induction successful.
engine_0.induction: Status returned by engine for induction: pass

summary: successful proof by k-induction.
DONE (PASS, rc=0)
```

---

## 10. Checking the Result

After the proof:

```bash
cat async_fifo/status
```

You can also search the generated logs:

```bash
grep -R "PASS\|FAIL\|ERROR\|Status" async_fifo/engine_0/
```

If a formal property fails, inspect the generated trace files inside:

```text
async_fifo/engine_0/
```

A VCD trace can be opened with:

```bash
gtkwave <trace-file>.vcd
```

---

## 11. Formal Properties We Checked

The formal harness checks basic safety and reset behavior.

### Read reset implies empty

```systemverilog
always @(posedge formal_clk) begin
    if (rd_rst)
        assert(empty);
end
```

This checks that the FIFO is empty while the read side is reset.

### Write reset implies not full

```systemverilog
always @(posedge formal_clk) begin
    if (wr_rst)
        assert(!full);
end
```

This checks that the FIFO is not full while the write side is reset.

### Full and empty cannot both be true

```systemverilog
always @(posedge formal_clk) begin
    assert(!(full && empty));
end
```

This is a basic FIFO safety property.

### Cover empty

```systemverilog
always @(posedge formal_clk) begin
    if (!rd_rst)
        cover(empty);
end
```

This asks the formal engine to find a reachable state where the FIFO is empty.

### Cover full

```systemverilog
always @(posedge formal_clk) begin
    if (!wr_rst)
        cover(full);
end
```

This asks the formal engine to find a reachable state where the FIFO becomes full.

---

## 12. Assertions, Assumptions, and Covers

### Assertion

An assertion describes something that must never be violated.

Example:

```systemverilog
assert(!(full && empty));
```

If the formal engine finds a counterexample, the property fails.

### Assumption

An assumption constrains the environment.

For example, a formal model can use assumptions to describe legal clock or reset behavior.

### Cover

A cover statement asks: **Can the design reach this state?**

Example:

```systemverilog
cover(full);
```

A successful cover does not prove that the state is always safe. It demonstrates reachability.

---

## 13. Safety vs Reachability

A useful distinction learned during this project:

### Safety

Safety asks: **Can something bad ever happen?**

```systemverilog
assert(!(full && empty));
```

### Reachability / Cover

Cover asks: **Can something interesting happen?**

```systemverilog
cover(full);
```

So:

```text
assert = prove something cannot happen
cover  = find a way something can happen
```

---

## 14. K-Induction

The formal run uses:

```text
smtbmc z3
```

with:

```text
depth 20
```

The successful result included:

```text
basecase: pass
induction: pass
```

K-induction works by combining:

1. **A base case** — the property holds for the initial number of steps.
2. **An induction step** — if the property holds over the required history, it continues to hold.

This is one reason formal verification can prove properties beyond a fixed simulation test sequence.

---

## 15. SVA: `|->` vs `|=>`

We also looked at SystemVerilog Assertions (SVA).

Example:

```systemverilog
property fifo_empty_after_reset;
    @(posedge rd_clk)
    rd_rst |=> empty;
endproperty
```

The important difference is:

| Operator | Meaning               | Timing              |
|----------|------------------------|----------------------|
| `\|->`   | overlapped implication | same sampled cycle   |
| `\|=>`   | non-overlapped implication | next sampled cycle |

Therefore:

```systemverilog
rd_rst |-> empty
```

means: *If reset is high at this clock edge, empty must be high at this same sampled edge.*

While:

```systemverilog
rd_rst |=> empty
```

means: *If reset is high at this clock edge, empty must be high at the next sampled clock edge.*

---

## 16. What We Learned

The main concepts covered in this project were:

- Asynchronous FIFO architecture
- Separate read and write clock domains
- Binary read/write pointers
- Binary-to-Gray conversion
- Gray-code pointers for CDC
- Two-flop synchronizers
- Full detection
- Empty detection
- Extra pointer bit
- SystemVerilog `always_ff`
- SystemVerilog assertions
- `|->` and `|=>`
- Yosys synthesis/formal frontend
- SymbiYosys
- Z3 SMT solving
- Bounded proof depth
- Base-case checking
- K-induction
- Safety properties
- Cover/reachability properties
- Verilator simulation
- GTKWave waveform debugging

---

## 17. Important Limitation of the Current Formal Model

The current formal harness is intentionally learning-oriented.

It uses a `formal_clk` and allows the write/read clock values to be unconstrained with `$anyseq`:

```systemverilog
always @(posedge formal_clk) begin
    wr_clk <= $anyseq;
    rd_clk <= $anyseq;
end
```

This is useful for learning the formal workflow, but it should not be interpreted as a complete, production-quality proof of asynchronous CDC correctness.

The current FIFO interface also has no explicit:

- `wr_en`
- `rd_en`

signals. The current RTL writes on a write-clock edge when the FIFO is not full, and reads on a read-clock edge when the FIFO is not empty.

These are deliberate characteristics of the current learning project.

---

## 18. Possible Next Steps

A stronger verification project could be developed in stages:

### Phase 1 — Current project
- Basic FIFO RTL
- Simulation
- Basic assertions
- Cover properties
- Yosys/SBY/Z3 proof

### Phase 2 — Pointer verification

Add stronger properties for:
- Pointer progression
- Pointer stability
- Gray-code transitions
- Full detection
- Empty detection

### Phase 3 — CDC verification

Verify:
- Correct pointer synchronization
- Reset crossing behavior
- Clock-domain interaction
- CDC assumptions

### Phase 4 — Data integrity

Build a formal reference model or scoreboarding approach to prove:
- data written → data eventually read

while preserving FIFO ordering.

### Phase 5 — Production-style interface

Add explicit:
- `wr_en`
- `rd_en`

signals and verify:
- No write when full
- No read when empty
- Data ordering
- Occupancy behavior
- Simultaneous read/write behavior

---

## 19. Useful Commands — Quick Reference

### Simulation

```bash
verilator --binary --timing --trace async_fifo.sv async_tb.sv --top-module async_tb
./obj_dir/Vasync_tb
gtkwave async_fifo.vcd
```

### Formal

```bash
rm -rf async_fifo
sby -f async_fifo.sby
```

### Check status

```bash
cat async_fifo/status
```

### Search logs

```bash
grep -R "PASS\|FAIL\|ERROR\|Status" async_fifo/engine_0/
```

---

## 20. Final Verification Result

For the working version of the project, SymbiYosys completed successfully with:

```text
Base case: PASS
Induction: PASS
Overall proof: PASS
```

The project therefore demonstrates a complete basic workflow:

```text
Write RTL
   ↓
Simulate with Verilator
   ↓
Inspect waveforms with GTKWave
   ↓
Write formal properties
   ↓
Run Yosys/SymbiYosys
   ↓
Solve with Z3
   ↓
Inspect PASS/FAIL and traces
```

---

## Conclusion

This project was built as a practical introduction to asynchronous FIFO design and formal verification.

The most important takeaway is that simulation and formal verification serve different purposes:

- **Simulation** explores selected scenarios.
- **Formal verification** searches a much larger state space for violations of explicitly stated properties.

The asynchronous FIFO also demonstrates why CDC design requires special care: pointers cannot simply be transferred as ordinary binary counters between unrelated clock domains. Gray coding and synchronization are fundamental parts of the architecture.

The current implementation is a solid learning baseline that can be extended into a more complete CDC and data-integrity verification environment.