`timescale 1ns/1ps

module async_tb;


// ------------------------------------------------------------
// Parameters
// ------------------------------------------------------------
parameter int DATAWIDTH = 3;
parameter int DEPTH     = 8;

// ------------------------------------------------------------
// Signals
// ------------------------------------------------------------
logic rd_clk, wr_clk;
logic rd_rst, wr_rst;
logic full, empty;

logic [DATAWIDTH-1:0] wr_data;
logic [DATAWIDTH-1:0] rd_data;

// Optional enables
logic wr_en, rd_en;


// ------------------------------------------------------------
// DUT
// ------------------------------------------------------------
async_fifo #(
    .DATAWIDTH(DATAWIDTH),
    .DEPTH(DEPTH)
) uut (
    .rd_clk  (rd_clk),
    .rd_rst  (rd_rst),
    .rd_data (rd_data),
    .wr_clk  (wr_clk),
    .wr_rst  (wr_rst),
    .wr_data (wr_data),
    .full    (full),
    .empty   (empty)
);


// ------------------------------------------------------------
// Simulation Setup
// ------------------------------------------------------------
initial begin
    $dumpfile("async_fifo.vcd");
    $dumpvars(0, async_tb);

    wr_clk  = 0;
    rd_clk  = 0;
    wr_rst  = 1;
    rd_rst  = 1;
    wr_en   = 0;
    rd_en   = 0;
    wr_data = '0;

    repeat (2) @(posedge wr_clk);

    wr_rst = 0;
    rd_rst = 0;

    #1000;
    $finish;
end


// ------------------------------------------------------------
// Clock Generation
// ------------------------------------------------------------
always #5  wr_clk = ~wr_clk;
always #10 rd_clk = ~rd_clk;


// ============================================================
// FORMAL / ASSERTION CONCEPTS
// ============================================================


// ------------------------------------------------------------
// 1. RESET PROPERTIES
// ------------------------------------------------------------

// FIFO must indicate empty after read reset
property fifo_empty_after_reset;
    @(posedge rd_clk)
    rd_rst |=> empty;
endproperty

assert property (fifo_empty_after_reset)
    else $error("FORMAL ASSERTION FAILED: FIFO not empty after reset");


// ------------------------------------------------------------
// 2. FULL FLAG SAFETY
// ------------------------------------------------------------

// When FIFO is full, a write should not be accepted.
// This assumes wr_en exists in the actual FIFO design.
property no_write_when_full;
    @(posedge wr_clk)
    disable iff (wr_rst)
    full && wr_en |=> full;
endproperty

assert property (no_write_when_full)
    else $error("FORMAL ASSERTION FAILED: Write attempted while FIFO full");


// ------------------------------------------------------------
// 3. EMPTY FLAG SAFETY
// ------------------------------------------------------------

// When FIFO is empty, a read should not be accepted.
property no_read_when_empty;
    @(posedge rd_clk)
    disable iff (rd_rst)
    empty && rd_en |=> empty;
endproperty

assert property (no_read_when_empty)
    else $error("FORMAL ASSERTION FAILED: Read attempted while FIFO empty");


// ------------------------------------------------------------
// 4. WRITE DATA STABILITY
// ------------------------------------------------------------

// Data should remain stable while no write operation occurs.
property write_data_stable;
    @(posedge wr_clk)
    disable iff (wr_rst)
    !wr_en |=> $stable(wr_data);
endproperty

assert property (write_data_stable)
    else $error("FORMAL ASSERTION FAILED: Write data changed unexpectedly");


// ------------------------------------------------------------
// 5. MUTUAL FLAG CHECK
// ------------------------------------------------------------

// A FIFO generally cannot be FULL and EMPTY simultaneously,
// except potentially during reset/initialization depending
// on implementation.
property not_full_and_empty;
    @(posedge wr_clk)
    disable iff (wr_rst || rd_rst)
    !(full && empty);
endproperty

assert property (not_full_and_empty)
    else $error("FORMAL ASSERTION FAILED: FIFO is both FULL and EMPTY");


// ------------------------------------------------------------
// 6. COVER PROPERTY
// ------------------------------------------------------------

// Check whether the FIFO can reach a full state.
property fifo_reaches_full;
    @(posedge wr_clk)
    disable iff (wr_rst)
    ##[1:$] full;
endproperty

cover property (fifo_reaches_full);


// Check whether FIFO can become empty.
property fifo_reaches_empty;
    @(posedge rd_clk)
    disable iff (rd_rst)
    ##[1:$] empty;
endproperty

cover property (fifo_reaches_empty);


// ------------------------------------------------------------
// FORMAL ASSUMPTION EXAMPLES
// ------------------------------------------------------------

`ifdef FORMAL

// Assume resets are eventually released
assume property (
    @(posedge wr_clk)
    wr_rst |-> ##[1:5] !wr_rst
);

assume property (
    @(posedge rd_clk)
    rd_rst |-> ##[1:5] !rd_rst
);

// Assume write data can take any valid value
// This allows the formal tool to explore all data combinations.

`endif

endmodule
