module async_fifo_formal;

    parameter integer DATAWIDTH = 3;
    parameter integer DEPTH     = 8;

    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH;

    // ============================================================
    // FORMAL CLOCK
    // ============================================================
    //
    // One formal sampling clock is used by the verification
    // environment. The two FIFO clocks are abstract inputs.
    //
    // They are intentionally not generated with # delays.
    //

    reg formal_clk;

    reg wr_clk;
    reg rd_clk;

    reg wr_rst;
    reg rd_rst;

    reg [DATAWIDTH-1:0] wr_data;

    wire full;
    wire empty;
    wire [DATAWIDTH-1:0] rd_data;

    // ============================================================
    // DUT
    // ============================================================

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

    // ============================================================
    // INITIAL CONDITIONS
    // ============================================================

    initial begin
        formal_clk = 1'b0;

        wr_clk = 1'b0;
        rd_clk = 1'b0;

        wr_rst = 1'b1;
        rd_rst = 1'b1;

        wr_data = '0;
    end

    // ============================================================
    // FORMAL SAMPLING CLOCK
    // ============================================================

    always begin
        #1 formal_clk = ~formal_clk;
    end

    // ============================================================
    // ABSTRACT CLOCKS
    // ============================================================
    //
    // Each clock is allowed to change independently.
    //

    always @(posedge formal_clk) begin
        wr_clk <= $anyseq;
        rd_clk <= $anyseq;
    end

    // ============================================================
    // RESET
    // ============================================================

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

    // ============================================================
    // WRITE DATA
    // ============================================================

    always @(posedge formal_clk) begin
        if (!wr_rst)
            wr_data <= $anyseq;
    end

    // ============================================================
    // BASIC SAFETY ASSERTIONS
    // ============================================================

    // ------------------------------------------------------------
    // Property 1:
    // Read reset implies empty.
    // ------------------------------------------------------------

    always @(posedge formal_clk) begin
        if (rd_rst)
            assert(empty);
    end

    // ------------------------------------------------------------
    // Property 2:
    // Write reset implies not full.
    // ------------------------------------------------------------

    always @(posedge formal_clk) begin
        if (wr_rst)
            assert(!full);
    end

    // ------------------------------------------------------------
    // Property 3:
    // FIFO must not be simultaneously full and empty.
    // ------------------------------------------------------------

    always @(posedge formal_clk) begin
        assert(!(full && empty));
    end

    // ============================================================
    // COVER PROPERTIES
    // ============================================================

    // ------------------------------------------------------------
    // Cover 1:
    // FIFO reaches empty.
    // ------------------------------------------------------------

    always @(posedge formal_clk) begin
        if (!rd_rst)
            cover(empty);
    end

    // ------------------------------------------------------------
    // Cover 2:
    // FIFO reaches full.
    // ------------------------------------------------------------

    always @(posedge formal_clk) begin
        if (!wr_rst)
            cover(full);
    end

endmodule