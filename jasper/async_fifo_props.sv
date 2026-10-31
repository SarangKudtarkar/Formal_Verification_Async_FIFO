// ============================================================================
// async_fifo_props.sv  -  JasperGold FPV property module for async_fifo
//
// Clock model: wr_clk and rd_clk are truly independent (declared as two
// separate clocks in the Tcl script), so every property here must hold for any
// interleaving of write/read clock edges.
//
// NOTE: because the clocks are independent, the pointer synchronizers make the
// full/empty flags PESSIMISTIC (stale).  Properties such as !(full && empty)
// are therefore NOT valid here - they only "pass" in a lockstep (single-clock)
// model.  Instead we check that the flags are SOUND (never optimistic) against
// the true occupancy, which is what prevents overflow / underflow.
// ============================================================================

`timescale 1ns/1ps

`define ASSERT_BOTH(NAME, EXPR)                                                 \
    a_``NAME``_wclk : assert property (@(posedge wr_clk) disable iff (rst) EXPR); \
    a_``NAME``_rclk : assert property (@(posedge rd_clk) disable iff (rst) EXPR);

module async_fifo_props #(
    parameter integer DATAWIDTH = 3,
    parameter integer DEPTH     = 8,
    localparam integer PW       = $clog2(DEPTH)
)(
    input logic                 wr_clk,
    input logic                 rd_clk,
    input logic                 rst,          // drives wr_rst and rd_rst

    // DUT ports
    input logic [DATAWIDTH-1:0] wr_data,
    input logic                 full,
    input logic                 empty,
    input logic [DATAWIDTH-1:0] rd_data,

    // DUT internals (white-box, used for strengthening lemmas)
    input logic [PW:0]          wr_ptr_bin,
    input logic [PW:0]          rd_ptr_bin,
    input logic [PW:0]          wr_ptr_gray,
    input logic [PW:0]          rd_ptr_gray,
    input logic [PW:0]          wr_ptr_gray_sync2,   // wr ptr as seen in rd domain
    input logic [PW:0]          rd_ptr_gray_sync2,   // rd ptr as seen in wr domain

    // Free (symbolic) inputs for the data-integrity check
    input logic [DATAWIDTH-1:0] sym_data,
    input logic [PW:0]          sym_idx
);

    // Unsigned constants (avoid signed/unsigned compares against `integer`)
    localparam logic [PW+1:0] DEPTH_U = DEPTH;
    localparam logic [PW:0]   LAST_PTR = 2*DEPTH - 1;

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    function automatic logic [PW:0] b2g(input logic [PW:0] b);
        return (b >> 1) ^ b;
    endfunction

    function automatic logic [PW:0] g2b(input logic [PW:0] g);
        logic [PW:0] b;
        b[PW] = g[PW];
        for (int i = PW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    // ------------------------------------------------------------------------
    // Reference model: independent write / read counters (mod 2*DEPTH)
    // A write happens on a wr_clk edge when !full, a read on a rd_clk edge
    // when !empty - this is the (enable-less) protocol of async_fifo.
    // ------------------------------------------------------------------------
    logic [PW:0] mdl_wr_cnt, mdl_rd_cnt;

    always_ff @(posedge wr_clk or posedge rst)
        if (rst)        mdl_wr_cnt <= '0;
        else if (!full) mdl_wr_cnt <= mdl_wr_cnt + 1'b1;

    always_ff @(posedge rd_clk or posedge rst)
        if (rst)         mdl_rd_cnt <= '0;
        else if (!empty) mdl_rd_cnt <= mdl_rd_cnt + 1'b1;

    // True occupancy (both domains, global view - only legal in formal)
    wire [PW:0] occ_mdl = mdl_wr_cnt - mdl_rd_cnt;
    wire [PW:0] occ     = wr_ptr_bin - rd_ptr_bin;

    // Synchronizer lag / visibility (white-box lemmas)
    wire [PW:0] wr_seen_by_rd = g2b(wr_ptr_gray_sync2);
    wire [PW:0] rd_seen_by_wr = g2b(rd_ptr_gray_sync2);
    wire [PW:0] wlag  = wr_ptr_bin   - wr_seen_by_rd;  // writes not yet visible to reader
    wire [PW:0] rview = wr_seen_by_rd - rd_ptr_bin;    // items reader believes are available
    wire [PW:0] rlag  = rd_ptr_bin   - rd_seen_by_wr;  // reads not yet visible to writer

    // ------------------------------------------------------------------------
    // ENVIRONMENT ASSUMPTIONS
    // ------------------------------------------------------------------------

    // Reset is applied once at power-on (JasperGold reset sequence) and never
    // re-asserted.  wr_up / rd_up are set by the first clock edge seen with
    // reset low.
    logic wr_up, rd_up;
    always_ff @(posedge wr_clk or posedge rst) if (rst) wr_up <= 1'b0; else wr_up <= 1'b1;
    always_ff @(posedge rd_clk or posedge rst) if (rst) rd_up <= 1'b0; else rd_up <= 1'b1;

    m_no_rerst_w : assume property (@(posedge wr_clk) wr_up |-> !rst);
    m_no_rerst_r : assume property (@(posedge rd_clk) rd_up |-> !rst);

    // Symbolic tracked item is a constant for the whole run.
    m_sym_stable_wd_w : assume property (@(posedge wr_clk) $stable(sym_data));
    m_sym_stable_wd_r : assume property (@(posedge rd_clk) $stable(sym_data));
    m_sym_stable_ix_w : assume property (@(posedge wr_clk) $stable(sym_idx));
    m_sym_stable_ix_r : assume property (@(posedge rd_clk) $stable(sym_idx));

    // The write whose (mod 2*DEPTH) sequence number equals sym_idx carries
    // sym_data.  Everything else on wr_data is completely unconstrained.
    m_tracked_write : assume property (@(posedge wr_clk) disable iff (rst)
        (!full && (mdl_wr_cnt == sym_idx)) |-> (wr_data == sym_data));

    // ------------------------------------------------------------------------
    // ASSERTIONS
    // ------------------------------------------------------------------------

    // --- Reset behaviour (per domain) ---------------------------------------
    a_rst_empty : assert property (@(posedge rd_clk) rst |-> (empty && rd_data == '0));
    a_rst_notfull : assert property (@(posedge wr_clk) rst |-> !full);

    // --- Safety: no overflow, no underflow ----------------------------------
    // Modular occupancy can only exceed DEPTH if the writer overran the reader
    // (overflow) or the reader overtook the writer (underflow, appears as a
    // "negative" occupancy = large modular value).
    `ASSERT_BOTH(no_overflow_underflow, (occ_mdl <= DEPTH_U))

    // --- Flags are sound (never optimistic) ---------------------------------
    `ASSERT_BOTH(full_sound,  ((occ_mdl == DEPTH_U) |-> full))
    `ASSERT_BOTH(empty_sound, ((occ_mdl == 0)     |-> empty))

    // --- Pointer structure ---------------------------------------------------
    `ASSERT_BOTH(wptr_matches_model, (wr_ptr_bin == mdl_wr_cnt))
    `ASSERT_BOTH(rptr_matches_model, (rd_ptr_bin == mdl_rd_cnt))
    `ASSERT_BOTH(wgray_encoding,     (wr_ptr_gray == b2g(wr_ptr_bin)))
    `ASSERT_BOTH(rgray_encoding,     (rd_ptr_gray == b2g(rd_ptr_bin)))

    // Gray pointers that cross the clock domain change by at most 1 bit per
    // source-clock edge (this is what makes the 2-FF synchronizer safe).
    a_wgray_onebit : assert property (@(posedge wr_clk) disable iff (rst)
        $countones(wr_ptr_gray ^ $past(wr_ptr_gray)) <= 1);
    a_rgray_onebit : assert property (@(posedge rd_clk) disable iff (rst)
        $countones(rd_ptr_gray ^ $past(rd_ptr_gray)) <= 1);

    // --- CDC lemmas (strengthening) -----------------------------------------
    // Synchronized pointers only ever lag the real ones, never lead:
    //   occupancy = (writes reader has not seen yet) + (items reader can see)
    `ASSERT_BOTH(sync_view_split, (({1'b0, wlag} + {1'b0, rview}) == {1'b0, occ}))
    // The writer's stale view of occupancy never exceeds DEPTH, which is what
    // keeps `full` conservative.
    `ASSERT_BOTH(stale_occ_bound, (({1'b0, occ} + {1'b0, rlag}) <= DEPTH_U))

    // --- Data integrity (symbolic scoreboard) --------------------------------
    // Pick one arbitrary write (sequence number == sym_idx) and give it an
    // arbitrary value (sym_data).  When the matching read happens, the data
    // that appears on rd_data (registered, one rd_clk later) must be that
    // value.  Because sym_idx / sym_data are free, this proves ordering and
    // no-corruption / no-loss / no-duplication for every item.
    a_data_integrity : assert property (@(posedge rd_clk) disable iff (rst)
        (!empty && (mdl_rd_cnt == sym_idx)) |=> (rd_data == sym_data));

    // ------------------------------------------------------------------------
    // COVER PROPERTIES (reachability / anti-vacuity)
    // ------------------------------------------------------------------------
    c_full           : cover property (@(posedge wr_clk) disable iff (rst) full);
    c_empty_after_rd : cover property (@(posedge rd_clk) disable iff (rst) !empty ##1 empty);
    c_occ_full       : cover property (@(posedge wr_clk) disable iff (rst) occ_mdl == DEPTH_U);
    c_fill_then_drain: cover property (@(posedge rd_clk) disable iff (rst)
                           (occ_mdl == DEPTH_U) ##[1:$] (occ_mdl == 0));
    // Expected to be REACHABLE with independent clocks: both flags high while
    // pointer synchronizers are still catching up (pessimistic flags).
    c_full_and_empty : cover property (@(posedge wr_clk) disable iff (rst) full && empty);
    c_wptr_wrap      : cover property (@(posedge wr_clk) disable iff (rst)
                           (wr_ptr_bin == '0) && ($past(wr_ptr_bin) == LAST_PTR));
    // Tracked item is actually written and read (proves the data assumption
    // is not over-constraining and the scoreboard is live).
    c_tracked_write  : cover property (@(posedge wr_clk) disable iff (rst)
                           !full && (mdl_wr_cnt == sym_idx));
    c_tracked_read   : cover property (@(posedge rd_clk) disable iff (rst)
                           !empty && (mdl_rd_cnt == sym_idx) ##1 (rd_data == sym_data));

endmodule
