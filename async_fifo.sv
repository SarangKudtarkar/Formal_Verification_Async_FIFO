`timescale 1ns/1ps

module async_fifo #(
    parameter integer DATAWIDTH = 3,
    parameter integer DEPTH     = 8
)(
    input  logic wr_clk,
    input  logic wr_rst,

    input  logic rd_clk,
    input  logic rd_rst,

    input  logic [DATAWIDTH-1:0] wr_data,

    output logic full,
    output logic empty,

    output logic [DATAWIDTH-1:0] rd_data
);

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------

    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH;

    // This implementation uses standard Gray-pointer full
    // detection and therefore requires a power-of-two DEPTH.
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
            $error("DEPTH must be a power of 2 and >= 2");
    end

    // ------------------------------------------------------------
    // Memory
    // ------------------------------------------------------------

    logic [DATAWIDTH-1:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------
    // Binary pointers
    // Extra MSB is used to distinguish full from empty.
    // ------------------------------------------------------------

    logic [PTR_WIDTH:0] wr_ptr_bin;
    logic [PTR_WIDTH:0] rd_ptr_bin;

    logic [PTR_WIDTH:0] wr_ptr_bin_next;
    logic [PTR_WIDTH:0] rd_ptr_bin_next;

    // ------------------------------------------------------------
    // Gray pointers
    // ------------------------------------------------------------

    logic [PTR_WIDTH:0] wr_ptr_gray;
    logic [PTR_WIDTH:0] rd_ptr_gray;

    logic [PTR_WIDTH:0] wr_ptr_gray_next;
    logic [PTR_WIDTH:0] rd_ptr_gray_next;

    // ------------------------------------------------------------
    // Synchronizers
    // ------------------------------------------------------------

    logic [PTR_WIDTH:0] rd_ptr_gray_sync1;
    logic [PTR_WIDTH:0] rd_ptr_gray_sync2;

    logic [PTR_WIDTH:0] wr_ptr_gray_sync1;
    logic [PTR_WIDTH:0] wr_ptr_gray_sync2;

    // ------------------------------------------------------------
    // Next write pointer
    //
    // With the current interface, a write occurs on every
    // write-clock edge while the FIFO is not full.
    // ------------------------------------------------------------

    always_comb begin
        if (!full)
            wr_ptr_bin_next = wr_ptr_bin + 1'b1;
        else
            wr_ptr_bin_next = wr_ptr_bin;
    end

    // Binary -> Gray
    always_comb begin
        wr_ptr_gray_next =
            (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    end

    // ------------------------------------------------------------
    // Next read pointer
    //
    // A read occurs on every read-clock edge while the FIFO
    // is not empty.
    // ------------------------------------------------------------

    always_comb begin
        if (!empty)
            rd_ptr_bin_next = rd_ptr_bin + 1'b1;
        else
            rd_ptr_bin_next = rd_ptr_bin;
    end

    // Binary -> Gray
    always_comb begin
        rd_ptr_gray_next =
            (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
    end

    // ------------------------------------------------------------
    // Write pointer
    // ------------------------------------------------------------

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
        end
        else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // ------------------------------------------------------------
    // Read pointer
    // ------------------------------------------------------------

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin  <= '0;
            rd_ptr_gray <= '0;
        end
        else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // ------------------------------------------------------------
    // Dual-clock memory write
    // ------------------------------------------------------------

    always_ff @(posedge wr_clk) begin
        if (!wr_rst && !full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // ------------------------------------------------------------
    // Dual-clock memory read
    // ------------------------------------------------------------

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data <= '0;
        else if (!empty)
            rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end

    // ------------------------------------------------------------
    // Read pointer synchronization into write clock domain
    // ------------------------------------------------------------

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

    // ------------------------------------------------------------
    // Write pointer synchronization into read clock domain
    // ------------------------------------------------------------

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

    // ------------------------------------------------------------
    // EMPTY generation
    // ------------------------------------------------------------

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            empty <= 1'b1;
        else
            empty <= (rd_ptr_gray_next == wr_ptr_gray_sync2);
    end

    // ------------------------------------------------------------
    // FULL generation
    //
    // Full condition for a Gray-coded asynchronous FIFO:
    // compare the next write pointer against the synchronized
    // read pointer with the two MSBs inverted.
    // ------------------------------------------------------------

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            full <= 1'b0;
        end
        else begin
            full <= (
                wr_ptr_gray_next ==
                {
                    ~rd_ptr_gray_sync2[PTR_WIDTH:PTR_WIDTH-1],
                     rd_ptr_gray_sync2[PTR_WIDTH-2:0]
                }
            );
        end
    end

endmodule