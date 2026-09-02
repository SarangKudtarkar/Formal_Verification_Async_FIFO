module async_fifo_formal;

    parameter integer DATAWIDTH = 3;
    parameter integer DEPTH     = 8;

    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH;

    reg formal_clk;

    reg wr_clk;
    reg rd_clk;

    reg wr_rst;
    reg rd_rst;

    reg [DATAWIDTH-1:0] wr_data;

    wire full;
    wire empty;
    wire [DATAWIDTH-1:0] rd_data;


    async_fifo #(
        .DATAWIDTH(DATAWIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .wr_clk  (wr_clk),
        .wr_rst  (wr_rst),

        .rd_clk  (rd_clk),
        .rd_rst  (rd_rst),

        .wr_data (wr_data),

        .full    (full),
        .empty   (empty),

        .rd_data (rd_data)
    );


    initial begin
        formal_clk = 1'b0;

        wr_clk = 1'b0;
        rd_clk = 1'b0;

        wr_rst = 1'b1;
        rd_rst = 1'b1;

        wr_data = '0;
    end


    always begin
        #1 formal_clk = ~formal_clk;
    end


    always @(posedge formal_clk) begin
        wr_clk <= $anyseq;
        rd_clk <= $anyseq;
    end


    always @(posedge formal_clk) begin
        if ($initstate) begin
            wr_rst <= 1'b1;
            rd_rst <= 1'b1;
        end
        else begin
            wr_rst <= 1'b0;
            rd_rst <= 1'b0;
        end
    end


    always @(posedge formal_clk) begin
        if (!wr_rst)
            wr_data <= $anyseq;
    end


    // RESET CHECKS

    always @(posedge formal_clk) begin
        if (rd_rst)
            assert(empty);
    end

    always @(posedge formal_clk) begin
        if (wr_rst)
            assert(!full);
    end


    // BASIC SAFETY

    always @(posedge formal_clk) begin
        assert(!(full && empty));
    end


    // COVER EMPTY

    always @(posedge formal_clk) begin
        if (!rd_rst)
            cover(empty);
    end


    // COVER FULL

    always @(posedge formal_clk) begin
        if (!wr_rst)
            cover(full);
    end

endmodule