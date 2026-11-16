/*
 *  Copyright (c) 2026 Eclipse Foundation
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */
/*
 *  Authors       : Ihsane TAHIR
 *  Creation Date : 2026
 *  Description   : Functional coverage collector for CVFPU conversion operations.
 *                  Subscribes to fpu_obs_txn items published by the monitor
 *                  and drives four covergroups:
 *
 *                    cg_f2i         — FCVT_F2I: stimulus kind (sat/NX/exact/neg-zero)
 *                                     crossed with src_fmt, int_dst_width,
 *                                     unsigned flag, and rnd_mode.
 *                                     Separate coverpoint for INT32 sign-extension.
 *
 *                    cg_i2f         — FCVT_I2F: stimulus kind (zero/INT_MIN/rounds)
 *                                     crossed with int_src_width, dst_fmt,
 *                                     unsigned flag, and rnd_mode.
 *
 *                    cg_f2f_widen   — FCVT_F2F widening (H→S, H→D, S→D):
 *                                     src/dst fmt × input class × output flags × rnd_mode.
 *
 *                    cg_f2f_narrow  — FCVT_F2F narrowing (S→H, D→H, D→S):
 *                                     src/dst fmt × input zone × output flags × rnd_mode.
 *
 */

class fpu_conv_cov extends uvm_subscriber #(fpu_obs_txn);
    `uvm_component_utils(fpu_conv_cov)

    // =========================================================================
    // Covergroup 2 — FCVT_F2I (Float-to-Integer)
    //   Stimulus kind (inferred from output flags + input operand) crossed with
    //   src_fmt, int destination width, unsigned flag, and rounding mode.
    //
    //   Separate coverpoint for sign-extension: tracks INT32 results on the
    //   64-bit datapath, in both signed and unsigned modes, with both positive
    //   and negative result sign bits.
    // =========================================================================
    covergroup cg_f2i with function sample(
        fpnew_pkg::classmask_e op_class, // Inferred from input operand classification
        fpu_obs_txn::f2i_domains_e f2i_domains,
        logic [1:0] src_fmt,       // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic       int_wide,      // 0 = INT32 dst, 1 = INT64 dst
        logic       unsigned_flag, // 0 = signed, 1 = unsigned
        logic [2:0] rnd_mode,
        logic [63:0] result
    );
        type_option.merge_instances = 1;
        option.get_inst_coverage = 1;
        option.per_instance = 1;

        cp_op_fclass: coverpoint op_class {
            bins neg_inf     = {fpnew_pkg::NEGINF};
            bins neg_normal  = {fpnew_pkg::NEGNORM};
            bins neg_subnorm = {fpnew_pkg::NEGSUBNORM};
            bins neg_zero    = {fpnew_pkg::NEGZERO};
            bins pos_zero    = {fpnew_pkg::POSZERO};
            bins pos_subnorm = {fpnew_pkg::POSSUBNORM};
            bins pos_normal  = {fpnew_pkg::POSNORM};
            bins pos_inf     = {fpnew_pkg::POSINF};
            bins snan        = {fpnew_pkg::SNAN};
            bins qnan        = {fpnew_pkg::QNAN};
        }

        // ---- Stimulus kind --------------------------------------------------
        // out-of-range positive
        // out-of-range negative
        // within range but not integer (inexact)
        // within range exact integer (no flags)
        cp_stim: coverpoint f2i_domains;

        // ---- Format / mode dimensions ---------------------------------------
        cp_src_fmt: coverpoint src_fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_int_wide: coverpoint int_wide {
            bins int32 = {1'b0};
            bins int64 = {1'b1};
        }

        cp_unsigned: coverpoint unsigned_flag {
            bins signed_op   = {1'b0};
            bins unsigned_op = {1'b1};
        }

        cp_rnd_mode: coverpoint rnd_mode {
            bins rne = {3'd0};
            bins rtz = {3'd1};
            bins rdn = {3'd2};
            bins rup = {3'd3};
            ignore_bins rmm = {3'd4};
        }

        // RV64 sign-extends W and WU results alike, so both signs must be
        // seen in both modes, including WU results with bit 31 set.
        cp_w_res_sign: coverpoint result[31] iff (!int_wide) {
            bins pos = {1'b0};
            bins neg = {1'b1};
        }

        cx_w_sext: cross cp_w_res_sign, cp_unsigned;

        // ---- Stimulus kind crossed with source format ----------------
        cp_stim_x_fmt: cross cp_stim, cp_src_fmt;

        cx_class_x_fmt: cross cp_op_fclass, cp_src_fmt;

        // ---- Inexact / saturation crossed with rounding mode ----------------
        cx_inexact_x_rnd: cross cp_stim, cp_rnd_mode, cp_src_fmt {
            // Only score inexact and out-of-range (saturation) against rnd_mode;
            // All exact integer-valued bins are rounding-mode independent.
            ignore_bins exact_rnd = binsof(cp_stim) intersect {
                fpu_obs_txn::F2I_BOUND_EXACT_INT32,
                fpu_obs_txn::F2I_BOUND_EXACT_UINT32,
                fpu_obs_txn::F2I_BOUND_EXACT_INT64,
                fpu_obs_txn::F2I_BOUND_EXACT_UINT64
            } && binsof(cp_rnd_mode);
        }
    endgroup : cg_f2i


    // =========================================================================
    // Covergroup 3 — FCVT_I2F (Integer-to-Float)
    //   Stimulus kind crossed with integer source width, FP destination format,
    //   unsigned flag, and rounding mode.
    //
    //   Specific bins:
    //     zero     — input = 0 → +0.0, no flags
    //     int_min  — INT_MIN (signed) → exact negative power-of-2, no NX
    //     rounds   — NX set: low-order bits lost in conversion
    //     other    — all remaining cases (large values that happen to be exact)
    // =========================================================================
    covergroup cg_i2f with function sample(
        fpu_obs_txn::i2f_stim_kind_e stim_kind,
        logic       int_wide,      // 0 = INT32 src, 1 = INT64 src
        logic [1:0] dst_fmt,       // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic       unsigned_flag, // 0 = signed, 1 = unsigned
        logic [2:0] rnd_mode,
        logic [4:0] status         // {NV,DZ,OF,UF,NX}
    );
        type_option.merge_instances = 1;
        option.get_inst_coverage = 1;
        option.per_instance = 1;

        cp_stim: coverpoint stim_kind;

        cp_int_wide: coverpoint int_wide {
            bins int32 = {1'b0};
            bins int64 = {1'b1};
        }

        cp_dst_fmt: coverpoint dst_fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_unsigned: coverpoint unsigned_flag {
            bins signed_op   = {1'b0};
            bins unsigned_op = {1'b1};
        }

        cp_rnd_mode: coverpoint rnd_mode {
            bins rne = {3'd0};
            bins rtz = {3'd1};
            bins rdn = {3'd2};
            bins rup = {3'd3};
            ignore_bins rmm = {3'd4};
        }

        // Integer sources can never underflow or be invalid, so these three
        // bins are the complete legal I2F status set; anything else is a bug.
        cp_status: coverpoint status {
            bins no_flags = {5'h00};
            bins nx_only  = {5'h01};
            bins of_nx    = {5'h05};
        }

        cx_stim_x_intw_x_fmt_x_unsign:
            cross cp_stim, cp_int_wide, cp_dst_fmt, cp_unsigned {
                
                // Ignore INT32_MIN when the operation is unsigned OR when the width is 64-bit
                ignore_bins ignore_int32_min = binsof(cp_stim) intersect {fpu_obs_txn::INT32_I2F_STIM_INT_MIN} && 
                                               (binsof(cp_unsigned.unsigned_op) || binsof(cp_int_wide.int64));
                
                // Ignore INT64_MIN when the operation is unsigned OR when the width is 32-bit
                ignore_bins ignore_int64_min = binsof(cp_stim) intersect {fpu_obs_txn::INT64_I2F_STIM_INT_MIN} && 
                                               (binsof(cp_unsigned.unsigned_op) || binsof(cp_int_wide.int32));
                
                ignore_bins ignore_rounds = binsof(cp_stim) intersect {fpu_obs_txn::I2F_STIM_ROUNDS} && 
                                            binsof(cp_int_wide.int32) && binsof(cp_dst_fmt.fp64); // INT32→FP64 rounds should not set NX, as all INT32 values are exactly representable in FP64
        }

        // ---- Rounding mode vs inexact result --------------------------------
        cx_rounds_x_rnd: cross cp_stim, cp_rnd_mode {
            // zero and int_min are exact; int_min × rnd_mode not meaningful.
            ignore_bins zero_rnd    = binsof(cp_stim) intersect {
                fpu_obs_txn::I2F_STIM_ZERO,
                fpu_obs_txn::INT32_I2F_STIM_INT_MIN,
                fpu_obs_txn::INT64_I2F_STIM_INT_MIN
            } && binsof(cp_rnd_mode);
        }

        cp_rounds: coverpoint stim_kind {
            bins rounds = {fpu_obs_txn::I2F_STIM_ROUNDS};
        }

        cx_rounds_x_rnd_x_fmt: cross cp_rounds, cp_rnd_mode, cp_dst_fmt;

        cx_status_x_fmt_x_intw: cross cp_status, cp_dst_fmt, cp_int_wide {
            // FP64's 53-bit significand holds every INT32 exactly.
            ignore_bins nx_ignore = binsof(cp_status.nx_only) &&
                                    binsof(cp_dst_fmt.fp64) && binsof(cp_int_wide.int32);
            // FP32/FP64 range far exceeds 2^64; only FP16 (max 65504) can overflow.
            ignore_bins of_ignore = binsof(cp_status.of_nx) &&
                                    (binsof(cp_dst_fmt.fp32) || binsof(cp_dst_fmt.fp64));
        }
    endgroup : cg_i2f

    // =========================================================================
    // Covergroup 4a — FCVT_F2F Widening (H→S, H→D, S→D)
    //   Covers input classes for every enabled widening pair and verifies the
    //   flag profile. Widening is always exact for normal and subnormal values
    //   → OF/UF/NX should never be set; the cross highlights unexpected flags.
    // =========================================================================
    covergroup cg_f2f_widen with function sample(
        logic [1:0] src_fmt,              // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic [1:0] dst_fmt,
        fpnew_pkg::classmask_e op_class, // Inferred from input operand classification
        logic [4:0] status,
        logic [2:0] rnd_mode
    );
        type_option.merge_instances = 1;
        option.get_inst_coverage = 1;
        option.per_instance = 1;

        cp_src_fmt: coverpoint src_fmt {
            bins fp32 = {2'b00};
            bins fp16 = {2'b10};
            // FP64 is the widest of the 3 enabled formats: widening can never
            // source from it (there's nothing wider to widen into).
            ignore_bins unreachable_src = {2'b01};
        }

        cp_dst_fmt: coverpoint dst_fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            // FP16 is the narrowest of the 3 enabled formats: widening can
            // never target it (there's nothing narrower to widen from).
            ignore_bins unreachable_dst = {2'b10};
        }

        cp_op_fclass: coverpoint op_class;

        // Expected: no flags for normal, subnorm, zero; possibly NV for sNaN.
        // Any OF/UF/NX on normal/subnorm widening would indicate a DUT bug.
        cp_flags: coverpoint status {
            bins no_flags = {5'h00};
            bins nv_only  = {5'h10};         // sNaN → qNaN, NV set
        }

        cp_rnd_mode: coverpoint rnd_mode {
            bins rne = {3'd0};
            bins rtz = {3'd1};
            bins rdn = {3'd2};
            bins rup = {3'd3};
            ignore_bins rmm = {3'd4};
        }

        // Which widening pair (H→S, H→D, S→D) was exercised. Same-format
        // "widening" (FP32->FP32) isn't a widen at all and can't be hit.
        cx_src_x_dst: cross cp_src_fmt, cp_dst_fmt {
            ignore_bins same_fmt = binsof(cp_src_fmt.fp32) && binsof(cp_dst_fmt.fp32);
        }

        cp_pair: coverpoint {src_fmt, dst_fmt} {
            bins h2s = {4'b10_00};
            bins h2d = {4'b10_01};
            bins s2d = {4'b00_01};
        }

        cx_pair_x_class: cross cp_pair, cp_op_fclass;
        cx_pair_x_flags: cross cp_pair, cp_flags;
    endgroup : cg_f2f_widen


    // =========================================================================
    // Covergroup 4b — FCVT_F2F Narrowing (S→H, D→H, D→S)
    //   Covers input zones for every enabled narrowing pair and crosses the
    //   resulting exception flags with rounding mode. All (non-ignored)
    //   rounding modes interact differently with the OF and UF boundaries.
    // =========================================================================
    covergroup cg_f2f_narrow with function sample(
        logic [1:0] src_fmt,              // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic [1:0] dst_fmt,
        fpnew_pkg::classmask_e op_class,
        fpnew_pkg::classmask_e res_class,
        logic [4:0] status,
        logic [2:0] rnd_mode
    );
        option.per_instance = 1;
        option.comment      = "FCVT_F2F narrowing (S->H, D->H, D->S): input zone x flags x rnd_mode";

        cp_src_fmt: coverpoint src_fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            // FP16 is the narrowest of the 3 enabled formats: narrowing can
            // never source from it (there's nothing narrower to narrow into).
            ignore_bins unreachable_src = {2'b10};
        }

        cp_dst_fmt: coverpoint dst_fmt {
            bins fp32 = {2'b00};
            bins fp16 = {2'b10};
            // FP64 is the widest of the 3 enabled formats: narrowing can
            // never target it (there's nothing wider to narrow from).
            ignore_bins unreachable_dst = {2'b01};
        }

        cp_op_fclass: coverpoint op_class;

        cp_res_fclass: coverpoint res_class {
            bins neg_inf     = {fpnew_pkg::NEGINF};
            bins neg_normal  = {fpnew_pkg::NEGNORM};
            bins neg_subnorm = {fpnew_pkg::NEGSUBNORM};
            bins neg_zero    = {fpnew_pkg::NEGZERO};
            bins pos_zero    = {fpnew_pkg::POSZERO};
            bins pos_subnorm = {fpnew_pkg::POSSUBNORM};
            bins pos_normal  = {fpnew_pkg::POSNORM};
            bins pos_inf     = {fpnew_pkg::POSINF};
            bins qnan        = {fpnew_pkg::QNAN};
            ignore_bins snan = {fpnew_pkg::SNAN};
        }

        cp_rnd_mode: coverpoint rnd_mode {
            bins rne = {3'd0};
            bins rtz = {3'd1};
            bins rdn = {3'd2};
            bins rup = {3'd3};
            ignore_bins rmm = {3'd4};
        }

        cp_fp_exception: coverpoint status {
            // Exact match for 0 (no bits set)
            bins NO_EXCEPTION = {'h0};
            wildcard bins NX = {5'b????1}; // Bit 0: Inexact
            wildcard bins UF = {5'b???1?}; // Bit 1: Underflow
            wildcard bins OF = {5'b??1??}; // Bit 2: Overflow
            wildcard bins NV = {5'b1????}; // Bit 4: Invalid Operation
        }

        // ---- Full zone × rnd_mode cross ------------------------------------
        cx_zone_x_rnd: cross cp_op_fclass, cp_rnd_mode;

        // Which narrowing pair (S→H, D→H, D→S) was exercised. Same-format
        // "narrowing" (FP32->FP32) isn't a narrow at all and can't be hit.
        cx_src_x_dst: cross cp_src_fmt, cp_dst_fmt {
            ignore_bins same_fmt = binsof(cp_src_fmt.fp32) && binsof(cp_dst_fmt.fp32);
        }

        cp_pair: coverpoint {src_fmt, dst_fmt} {
            bins s2h = {4'b00_10};
            bins d2h = {4'b01_10};
            bins d2s = {4'b01_00};
        }

        // OF and UF are where rounding mode changes the result (max-finite vs
        // INF, zero vs min-subnormal), so they are scored per mode and per pair.
        cp_of_uf: coverpoint status {
            wildcard bins OF = {5'b??1??};
            wildcard bins UF = {5'b???1?};
        }

        cx_pair_x_class:       cross cp_pair, cp_op_fclass;
        cx_pair_x_res_class:   cross cp_pair, cp_res_fclass;
        cx_pair_x_exception:   cross cp_pair, cp_fp_exception;
        cx_pair_x_of_uf_x_rnd: cross cp_pair, cp_of_uf, cp_rnd_mode;

    endgroup : cg_f2f_narrow


    // =========================================================================
    // UVM subscriber write() — routes each observed txn to the right covergroup
    // =========================================================================
    function void write(fpu_obs_txn t);
        case (t.m_operation)
            // -----------------------------------------------------------------
            FCVT_F2I: begin

                cg_f2i.sample(
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt),
                    t.classify_f2i_stim(),
                    t.src_fp_fmt(),
                    t.int_wide(),
                    t.unsigned_op(),
                    t.m_rm,
                    t.result_o
                );
            end

            // -----------------------------------------------------------------
            FCVT_I2F: begin
                cg_i2f.sample(
                    t.classify_i2f_stim(),
                    t.int_wide(),
                    t.m_fmt,
                    t.unsigned_op(),
                    t.m_rm,
                    t.status_o
                );
            end

            // -----------------------------------------------------------------
            FCVT_F2F: begin
                // Source format is carried in m_imm[1:0]; destination format in m_fmt
                logic [1:0] f2f_src_fmt = t.m_imm[1:0];
                logic [1:0] f2f_dst_fmt = t.m_fmt;
                int unsigned src_width = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(f2f_src_fmt));
                int unsigned dst_width = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(f2f_dst_fmt));

                if (src_width < dst_width) begin
                    cg_f2f_widen.sample(
                        f2f_src_fmt,
                        f2f_dst_fmt,
                        fpu_common_pkg::classify_operand(t.m_operand_a, f2f_src_fmt),
                        t.status_o,
                        t.m_rm
                    );
                end else if (src_width > dst_width) begin
                    cg_f2f_narrow.sample(
                        f2f_src_fmt,
                        f2f_dst_fmt,
                        fpu_common_pkg::classify_operand(t.m_operand_a, f2f_src_fmt),
                        fpu_common_pkg::classify_operand(t.result_o, f2f_dst_fmt),
                        t.status_o,
                        t.m_rm
                    );
                end
                // src_width == dst_width: not a real conversion, not expected from the sequencer
            end

            default: ; // non-conversion operations: ignore silently
        endcase
    endfunction : write


    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "fpu_conv_cov", uvm_component parent = null);
        super.new(name, parent);
        cg_f2i         = new();
        cg_i2f         = new();
        cg_f2f_widen   = new();
        cg_f2f_narrow  = new();
    endfunction : new

endclass : fpu_conv_cov
