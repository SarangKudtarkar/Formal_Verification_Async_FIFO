// ============================================================================
// async_fifo_fpv_top.sv  -  JasperGold FPV wrapper
//
// Wraps the unmodified async_fifo RTL and the property module.  All top-level
// inputs (clocks, reset, wr_data, sym_data, sym_idx) are free primary inputs
// for the formal tool.  A single async reset drives both domains.
// ============================================================================
`timescale 1ns/1ps

module async_fifo_fpv_top #(
    parameter integer DATAWIDTH = 3,
    parameter integer DEPTH     = 8,
    localparam integer PW       = $clog2(DEPTH)
)(
    input  logic                 wr_clk,
    input  logic                 rd_clk,
    input  logic                 rst,
    input  logic [DATAWIDTH-1:0] wr_data,

    // symbolic tracked item for the data-integrity check
    input  logic [DATAWIDTH-1:0] sym_data,
    input  logic [PW:0]          sym_idx,

    output logic                 full,
    output logic                 empty,
    output logic [DATAWIDTH-1:0] rd_data
);

    async_fifo #(
        .DATAWIDTH (DATAWIDTH),
        .DEPTH     (DEPTH)
    ) dut (
        .wr_clk  (wr_clk),
        .wr_rst  (rst),
        .rd_clk  (rd_clk),
        .rd_rst  (rst),
        .wr_data (wr_data),
        .full    (full),
        .empty   (empty),
        .rd_data (rd_data)
    );

    async_fifo_props #(
        .DATAWIDTH (DATAWIDTH),
        .DEPTH     (DEPTH)
    ) props (
        .wr_clk            (wr_clk),
        .rd_clk            (rd_clk),
        .rst               (rst),
        .wr_data           (wr_data),
        .full              (full),
        .empty             (empty),
        .rd_data           (rd_data),
        .wr_ptr_bin        (dut.wr_ptr_bin),
        .rd_ptr_bin        (dut.rd_ptr_bin),
        .wr_ptr_gray       (dut.wr_ptr_gray),
        .rd_ptr_gray       (dut.rd_ptr_gray),
        .wr_ptr_gray_sync2 (dut.wr_ptr_gray_sync2),
        .rd_ptr_gray_sync2 (dut.rd_ptr_gray_sync2),
        .sym_data          (sym_data),
        .sym_idx           (sym_idx)
    );

endmodule
