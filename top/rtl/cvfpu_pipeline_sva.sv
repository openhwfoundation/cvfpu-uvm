/*
 *  Copyright (c) 2026 Eclipse Foundation
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

module cvfpu_pipeline_sva
  import ariane_pkg::*;
#(
    parameter type fu_data_t = logic
) (
    input logic     clk_i,
    input logic     rst_ni,
    input logic     fpu_valid_i,
    input logic     fpu_ready_o,
    input fu_data_t fu_data_i
);

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

  // fpnew deasserts ready based on the opgroup of the incoming op, so the
  // stalled request's own opgroup is the one causing the backpressure.
  fpnew_pkg::opgroup_e stalled_grp;
  assign stalled_grp = get_opgroup(fu_data_i.operation);

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
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 1) && (stalled_grp == Opgroups[g])
    );
    c_backpressure_2: cover property (
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 2) && (stalled_grp == Opgroups[g])
    );
    c_backpressure_3plus: cover property (
      @(posedge clk_i) disable iff (!rst_ni) (bp_run_q >= 3) && (stalled_grp == Opgroups[g])
    );
  end

endmodule
