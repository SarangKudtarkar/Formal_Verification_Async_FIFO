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

    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH;

    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0)
            $error("DEPTH must be a power of 2 and >= 2");
    end

    logic [DATAWIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_WIDTH:0] wr_ptr_bin;
    logic [PTR_WIDTH:0] rd_ptr_bin;
    logic [PTR_WIDTH:0] wr_ptr_bin_next;
    logic [PTR_WIDTH:0] rd_ptr_bin_next;

    logic [PTR_WIDTH:0] wr_ptr_gray;
    logic [PTR_WIDTH:0] rd_ptr_gray;
    logic [PTR_WIDTH:0] wr_ptr_gray_next;
    logic [PTR_WIDTH:0] rd_ptr_gray_next;

    logic [PTR_WIDTH:0] rd_ptr_gray_sync1;
    logic [PTR_WIDTH:0] rd_ptr_gray_sync2;
    logic [PTR_WIDTH:0] wr_ptr_gray_sync1;
    logic [PTR_WIDTH:0] wr_ptr_gray_sync2;


    // WRITE POINTER NEXT

    always_comb begin
        if (!full)
            wr_ptr_bin_next = wr_ptr_bin + 1'b1;
        else
            wr_ptr_bin_next = wr_ptr_bin;
    end

    always_comb begin
        wr_ptr_gray_next =
            (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    end


    // READ POINTER NEXT

    always_comb begin
        if (!empty)
            rd_ptr_bin_next = rd_ptr_bin + 1'b1;
        else
            rd_ptr_bin_next = rd_ptr_bin;
    end

    always_comb begin
        rd_ptr_gray_next =
            (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
    end


    // WRITE POINTER

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


    // READ POINTER

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


    // MEMORY WRITE

    always_ff @(posedge wr_clk) begin
        if (!wr_rst && !full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end


    // MEMORY READ

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data <= '0;
        else if (!empty)
            rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end


    // READ POINTER SYNCHRONIZER
    // read domain -> write domain

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


    // WRITE POINTER SYNCHRONIZER
    // write domain -> read domain

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


    // EMPTY FLAG

    always_ff @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            empty <= 1'b1;
        else
            empty <= (rd_ptr_gray_next == wr_ptr_gray_sync2);
    end


    // FULL FLAG

    always_ff @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst)
            full <= 1'b0;
        else
            full <= (
                wr_ptr_gray_next ==
                {
                    ~rd_ptr_gray_sync2[PTR_WIDTH:PTR_WIDTH-1],
                     rd_ptr_gray_sync2[PTR_WIDTH-2:0]
                }
            );
    end

endmodule