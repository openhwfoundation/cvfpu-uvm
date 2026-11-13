/*
 *  Stage Occupancy Coverage: saturation and flush-vs-stage, bound directly
 *  into each fpnew datapath module (fpnew_fma, fpnew_noncomp,
 *  fpnew_cast_multi, fpnew_divsqrt_th_64_multi), reading each module's own
 *  internal per-register-stage valid signals (inp_pipe_valid_q/mid_pipe_valid_q/
 *  out_pipe_valid_q)
 */
module cvfpu_stage_occupancy_sva #(
    parameter int unsigned NumInpRegs = 1,
    parameter int unsigned NumMidRegs = 0,  // 0 = no mid stage (NONCOMP, DIVSQRT)
    parameter int unsigned NumOutRegs = 1
) (
    input logic clk_i,
    input logic rst_ni,
    input logic flush_i,
    input logic [0:NumInpRegs] inp_pipe_valid_q,
    input logic [0:NumMidRegs] mid_pipe_valid_q,  // unconnected/unused when NumMidRegs==0
    input logic [0:NumOutRegs] out_pipe_valid_q
);

  /* pragma translate_off */

  // -------------------------------------------------------------------------
  // 1. Saturation — 1 bin: every real register stage occupied simultaneously
  // -------------------------------------------------------------------------
  logic inp_all_valid, mid_all_valid, out_all_valid;

  if (NumInpRegs > 0) begin : gen_inp_full
    assign inp_all_valid = &inp_pipe_valid_q[1:NumInpRegs];
  end else begin : gen_inp_full_vacuous
    assign inp_all_valid = 1'b1;
  end

  if (NumMidRegs > 0) begin : gen_mid_full
    assign mid_all_valid = &mid_pipe_valid_q[1:NumMidRegs];
  end else begin : gen_mid_full_vacuous
    assign mid_all_valid = 1'b1;
  end

  if (NumOutRegs > 0) begin : gen_out_full
    assign out_all_valid = &out_pipe_valid_q[1:NumOutRegs];
  end else begin : gen_out_full_vacuous
    assign out_all_valid = 1'b1;
  end

  c_stage_saturation: cover property (
    @(posedge clk_i) disable iff (!rst_ni) inp_all_valid && mid_all_valid && out_all_valid
  );

  // -------------------------------------------------------------------------
  // 2. Flush vs. stage — NumInpRegs+NumMidRegs+NumOutRegs bins: one per real
  //    register stage, flush hitting while that exact stage holds a valid op
  // -------------------------------------------------------------------------
  for (genvar i = 1; i <= NumInpRegs; i++) begin : gen_flush_inp
    c_flush_vs_stage: cover property (
      @(posedge clk_i) disable iff (!rst_ni) flush_i && inp_pipe_valid_q[i]
    );
  end

  if (NumMidRegs > 0) begin : gen_flush_mid_present
    for (genvar i = 1; i <= NumMidRegs; i++) begin : gen_flush_mid
      c_flush_vs_stage: cover property (
        @(posedge clk_i) disable iff (!rst_ni) flush_i && mid_pipe_valid_q[i]
      );
    end
  end

  for (genvar i = 1; i <= NumOutRegs; i++) begin : gen_flush_out
    c_flush_vs_stage: cover property (
      @(posedge clk_i) disable iff (!rst_ni) flush_i && out_pipe_valid_q[i]
    );
  end

  /* pragma translate_on */

endmodule
