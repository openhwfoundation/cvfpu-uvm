/*
 *  Pipeline Behavior Coverage: backpressure duration, bound at the fpu_wrap
 *  boundary.
 *
 *  This is the one piece of Pipeline Behavior Coverage that is genuinely
 *  boundary-level rather than internal: it is purely about fpu_valid_i/
 *  fpu_ready_o stalling at the fpu_wrap port, which fpu_wrap itself observes
 *  directly (no internal datapath visibility needed).
 *
 *  Saturation, flush-vs-stage, and reset-vs-stage coverage used to live here
 *  too, inferred from a trans_id-keyed shadow model built purely from
 *  fpu_valid_i/fpu_ready_o/fpu_valid_o handshakes, comparing each outstanding
 *  transaction's elapsed-cycle "age" against each opgroup/format's
 *  NumPipeRegs. That comparison was conceptually wrong: NumPipeRegs is a
 *  pipeline-register-STAGE count, not a cycle latency — an operation can sit
 *  inside a single register stage for many cycles (most visibly for DIVSQRT,
 *  whose multi-cycle internal SRT FSM sits entirely within one register
 *  stage). That coverage has moved to cvfpu_stage_occupancy_sva.sv, bound
 *  directly into each datapath module (fpnew_fma/fpnew_noncomp/
 *  fpnew_cast_multi/fpnew_divsqrt_th_64_multi), which reads each module's own
 *  real per-stage valid signals instead of inferring position from boundary
 *  handshakes.
 *
 *  Backpressure's own cross-coverage dimension ("is an op of opgroup G in
 *  flight anywhere while the input is stalled for N cycles") still needs to
 *  know each outstanding trans_id's opgroup, since the op sitting at the
 *  input port while stalled isn't necessarily the (only) one backed up
 *  inside the pipeline. That needs no age/latency comparison, so the
 *  minimal valid_q/grp_q pair below is kept (unlike age_q/fmt_q/
 *  expected_latency(), which the conceptual bug above made meaningless).
 */
module cvfpu_pipeline_sva
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type fu_data_t = logic
) (
    input logic                             clk_i,
    input logic                             rst_ni,
    input logic                             flush_i,
    input logic                             fpu_valid_i,
    input logic                             fpu_ready_o,
    input fu_data_t                         fu_data_i,
    input logic [CVA6Cfg.TRANS_ID_BITS-1:0] fpu_trans_id_o,
    input logic                             fpu_valid_o
);

  /* pragma translate_off */

  localparam int unsigned NumSlots = 2 ** CVA6Cfg.TRANS_ID_BITS;

  // -------------------------------------------------------------------------
  // Opgroup decode helper (mirrors fpu_wrap.sv's own op decode; see
  // fpnew_pkg::get_opgroup() for the canonical grouping this is cross-checked
  // against).
  // -------------------------------------------------------------------------
  function automatic fpnew_pkg::opgroup_e get_opgroup(ariane_pkg::fu_op op);
    unique case (op)
      FADD, FSUB, FMUL, FMADD, FMSUB, FNMSUB, FNMADD: return fpnew_pkg::ADDMUL;
      FDIV, FSQRT: return fpnew_pkg::DIVSQRT;
      FMIN_MAX, FSGNJ, FMV_F2X, FMV_X2F, FCMP, FCLASS: return fpnew_pkg::NONCOMP;
      FCVT_F2F, FCVT_F2I, FCVT_I2F: return fpnew_pkg::CONV;
      default: return fpnew_pkg::NONCOMP;
    endcase
  endfunction

  localparam fpnew_pkg::opgroup_e Opgroups[4] = {
    fpnew_pkg::ADDMUL, fpnew_pkg::DIVSQRT, fpnew_pkg::NONCOMP, fpnew_pkg::CONV
  };

  // -------------------------------------------------------------------------
  // Minimal per-trans_id opgroup tracking: which opgroup each outstanding
  // trans_id belongs to, nothing more (no age, no format).
  // -------------------------------------------------------------------------
  logic                [NumSlots-1:0] valid_d, valid_q;
  fpnew_pkg::opgroup_e [NumSlots-1:0] grp_d, grp_q;

  logic accepted;
  assign accepted = fpu_valid_i && fpu_ready_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin : grp_track_ff
    if (!rst_ni) begin
      valid_q <= {NumSlots{1'b0}};
      grp_q   <= '{default: fpnew_pkg::NONCOMP};
    end else if (flush_i) begin
      valid_q <= {NumSlots{1'b0}};
      grp_q   <= '{default: fpnew_pkg::NONCOMP};
    end else begin
      valid_q <= valid_d;
      grp_q   <= grp_d;
    end
  end

  always_comb begin : grp_track_comb
    valid_d = valid_q;
    grp_d   = grp_q;
    if (accepted) begin
      valid_d[fu_data_i.trans_id] = 1'b1;
      grp_d[fu_data_i.trans_id]   = get_opgroup(fu_data_i.operation);
    end
    if (fpu_valid_o) valid_d[fpu_trans_id_o] = 1'b0;
  end

  function automatic bit any_in_flight(fpnew_pkg::opgroup_e grp);
    for (int i = 0; i < NumSlots; i++) begin
      if (valid_q[i] && grp_q[i] == grp) return 1'b1;
    end
    return 1'b0;
  endfunction

  // -------------------------------------------------------------------------
  // Backpressure duration — 12 bins: 4 opgroups x {1, 2, >=3 cycles}
  // -------------------------------------------------------------------------
  logic [3:0] bp_run_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) bp_run_q <= '0;
    else if (fpu_valid_i && !fpu_ready_o) bp_run_q <= bp_run_q + 1'b1;
    else bp_run_q <= '0;
  end

  for (genvar g = 0; g < 4; g++) begin : gen_bp_opgroup
    c_backpressure_1: cover property (
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 1) && any_in_flight(Opgroups[g])
    );
    c_backpressure_2: cover property (
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 2) && any_in_flight(Opgroups[g])
    );
    c_backpressure_3plus: cover property (
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 3) && any_in_flight(Opgroups[g])
    );
  end

  /* pragma translate_on */

endmodule
