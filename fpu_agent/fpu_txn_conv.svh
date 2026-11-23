/*
 *  Copyright (c) 2026 Eclipse Foundation
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */
/*
 *  Authors       : Ihsane TAHIR
 *  Creation Date : 2026
 *  Description   : 
 *  History       :
 */

class fpu_txn_conv extends fpu_txn;
    `uvm_object_utils(fpu_txn_conv)

    // =========================================================================
    // Stimulus category enum
    // =========================================================================
    typedef enum {
        // ---- FCVT_F2F stimuli -------------------------------------------
        F2F_BELLOW_SUBNORM,
        F2F_LOW_SUBNORM_UF,
        F2F_SUBNORM_NORM,
        F2F_LOW_NORMAL,
        F2F_NARROW_NORMAL,
        F2F_HIGH_NORMAL, 
        F2F_NARROW_OF,
        F2F_WIDEN,           // any input class on a widening pair
        F2F_NAN_INF,         // NaN / INF passthrough (any pair)
        // ---- Unconstrained ----------------------------------------------
        CONV_RANDOM          // fully random within {F2I, I2F, F2F}
    } conv_stim_e;

    typedef enum {
        F2F_D2S, F2F_D2H, F2F_S2H,   // narrowing
        F2F_S2D, F2F_H2S, F2F_H2D    // widening
    } f2f_pair_e;

    // FP32/FP64 sources: MID is in-range for every integer width, LOW_EDGE straddles
    // 2^31/2^32 and HIGH_EDGE straddles 2^63/2^64. FP16 can never reach 2^31, so its
    // edges are instead the exact-integer limit (2^11) and the top of its range (2^15).
    typedef enum {
        F2I_ZONE_MID,
        F2I_ZONE_LOW_EDGE,
        F2I_ZONE_HIGH_EDGE
    } f2i_zone_e;

    rand conv_stim_e m_conv_stim;
    rand f2f_pair_e  m_f2f_pair;
    rand f2i_zone_e  m_f2i_zone;

    // Biased exponent of the F2F source operand and the destination's limits
    // expressed in that same source encoding.
    rand int unsigned m_f2f_src_exp;
    rand int unsigned m_dst_snmin;
    rand int unsigned m_dst_nmin;
    rand int unsigned m_dst_nmax;
    rand int unsigned m_src_emax;

    // Mirrors m_imm[0] for F2I / I2F: 0 = INT32, 1 = INT64.
    // Keeping it as a named field makes inline constraints in sequences readable.
    rand logic m_int_wide;

    // =========================================================================
    // FP exponent boundary constants
    // =========================================================================
    localparam int unsigned B16 = fpnew_pkg::bias(fpnew_pkg::FP16);
    localparam int unsigned B32 = fpnew_pkg::bias(fpnew_pkg::FP32);
    localparam int unsigned B64 = fpnew_pkg::bias(fpnew_pkg::FP64);
    localparam int unsigned M16 = fpnew_pkg::man_bits(fpnew_pkg::FP16);
    localparam int unsigned M32 = fpnew_pkg::man_bits(fpnew_pkg::FP32);

    localparam logic [1:0] FMT_FP32 = 2'd0;
    localparam logic [1:0] FMT_FP64 = 2'd1;
    localparam logic [1:0] FMT_FP16 = 2'd2;

    // =========================================================================
    // Solve ordering
    // =========================================================================
    constraint order_stim_op_c   { solve m_conv_stim before m_operation;  }
    constraint order_stim_fmt_c  { solve m_conv_stim before m_fmt;        }
    constraint order_stim_imm_c  { solve m_conv_stim before m_imm;        }
    constraint order_stim_iw_c   { solve m_conv_stim before m_int_wide;   }
    constraint order_iw_imm_c    { solve m_int_wide  before m_imm;        }
    constraint order_stim_pair_c { solve m_conv_stim before m_f2f_pair;   }
    constraint order_pair_imm_c  { solve m_f2f_pair  before m_imm, m_fmt; }
    constraint order_pair_exp_c  { solve m_f2f_pair  before m_f2f_src_exp; }

    // =========================================================================
    // Restrict operation to conversions only
    // (Intersects with parent's fpu_operator_c — no conflict since all three
    //  conversion ops lie within the FADD..FCLASS range.)
    // =========================================================================
    constraint conv_op_c {
        m_operation inside {FCVT_F2I, FCVT_I2F, FCVT_F2F};
    }

    // =========================================================================
    // Stimulus distribution
    // =========================================================================
    constraint conv_stim_dist_c {
        m_conv_stim dist {
            F2F_BELLOW_SUBNORM := 2,
            F2F_LOW_SUBNORM_UF := 3,
            F2F_SUBNORM_NORM   := 10,
            F2F_LOW_NORMAL     := 5,
            F2F_NARROW_NORMAL  := 10,
            F2F_HIGH_NORMAL    := 5, 
            F2F_NARROW_OF      := 10,
            F2F_WIDEN          := 10,
            F2F_NAN_INF        := 5,
            CONV_RANDOM        := 50
        };
    }

    // =========================================================================
    // Bind each stimulus category to its operation
    // =========================================================================
    constraint conv_stim_op_bind_c {
        m_conv_stim != CONV_RANDOM -> m_operation == FCVT_F2F;
    }

    // =========================================================================
    // ---- FCVT_F2I constraints -----------------------------------------------
    // =========================================================================
    constraint f2i_zone_dist_c {
        m_f2i_zone dist { F2I_ZONE_MID := 40, F2I_ZONE_LOW_EDGE := 30, F2I_ZONE_HIGH_EDGE := 30 };
    }

    constraint f2i_fp32_operand_c {
        if (m_operation == FCVT_F2I) {
            if (m_fmt == FMT_FP32 && m_fp_op_type[0] == NORMAL) {
                (m_f2i_zone == F2I_ZONE_MID)       -> m_fp_single_operands[0].exponent inside {[B32 - 2  : B32 + 24]};
                (m_f2i_zone == F2I_ZONE_LOW_EDGE)  -> m_fp_single_operands[0].exponent inside {[B32 + 30 : B32 + 33]};
                (m_f2i_zone == F2I_ZONE_HIGH_EDGE) -> m_fp_single_operands[0].exponent inside {[B32 + 62 : B32 + 65]};
            }
            m_fp_single_operands[1] == '0; // Unused
        }
    }

    constraint f2i_fp64_operand_c {
        if (m_operation == FCVT_F2I) {
            if (m_fmt == FMT_FP64 && m_fp_op_type[0] == NORMAL) {
                (m_f2i_zone == F2I_ZONE_MID)       -> m_fp_double_operands[0].exponent inside {[B64 - 2  : B64 + 24]};
                (m_f2i_zone == F2I_ZONE_LOW_EDGE)  -> m_fp_double_operands[0].exponent inside {[B64 + 30 : B64 + 33]};
                (m_f2i_zone == F2I_ZONE_HIGH_EDGE) -> m_fp_double_operands[0].exponent inside {[B64 + 62 : B64 + 65]};
            }
            m_fp_double_operands[1] == '0; // Unused
        }
    }

    constraint f2i_fp16_operand_c {
        if (m_operation == FCVT_F2I) {
            if (m_fmt == FMT_FP16 && m_fp_op_type[0] == NORMAL) {
                (m_f2i_zone == F2I_ZONE_MID)       -> m_fp_half_operands[0].exponent inside {[B16 - 2  : B16 + 9]};
                (m_f2i_zone == F2I_ZONE_LOW_EDGE)  -> m_fp_half_operands[0].exponent inside {[B16 + 10 : B16 + 11]};
                (m_f2i_zone == F2I_ZONE_HIGH_EDGE) -> m_fp_half_operands[0].exponent inside {[B16 + 14 : B16 + 15]};
            }
            m_fp_half_operands[1] == '0; // Unused
        }
    }

    // =========================================================================
    // ---- FCVT_F2F constraints -----------------------------------------------
    // =========================================================================

    // m_imm[1:0] carries the source format, m_fmt the destination format.
    constraint f2f_direction_c {
        if (m_conv_stim != CONV_RANDOM) {
            m_conv_stim inside {F2F_BELLOW_SUBNORM, F2F_LOW_SUBNORM_UF, F2F_SUBNORM_NORM,
                                F2F_LOW_NORMAL, F2F_NARROW_NORMAL, F2F_HIGH_NORMAL,
                                F2F_NARROW_OF} -> m_f2f_pair inside {F2F_D2S, F2F_D2H, F2F_S2H};
            m_conv_stim == F2F_WIDEN       -> m_f2f_pair inside {F2F_S2D, F2F_H2S, F2F_H2D};

            (m_f2f_pair == F2F_D2S) -> { m_imm == FMT_FP64; m_fmt == FMT_FP32; }
            (m_f2f_pair == F2F_D2H) -> { m_imm == FMT_FP64; m_fmt == FMT_FP16; }
            (m_f2f_pair == F2F_S2H) -> { m_imm == FMT_FP32; m_fmt == FMT_FP16; }
            (m_f2f_pair == F2F_S2D) -> { m_imm == FMT_FP32; m_fmt == FMT_FP64; }
            (m_f2f_pair == F2F_H2S) -> { m_imm == FMT_FP16; m_fmt == FMT_FP32; }
            (m_f2f_pair == F2F_H2D) -> { m_imm == FMT_FP16; m_fmt == FMT_FP64; }
        }
    }

    // Destination limits re-expressed as source biased exponents:
    //   snmin = exponent of the destination's smallest subnormal
    //   nmin  = exponent of the destination's smallest normal
    //   nmax  = one below the destination's largest exponent, so the HIGH_NORMAL
    //           zone straddles the round-up-to-overflow boundary
    constraint f2f_narrow_limits_c {
        (m_f2f_pair == F2F_D2S) -> { m_dst_snmin == B64 + 1 - B32 - M32; m_dst_nmin == B64 + 1 - B32;
                                     m_dst_nmax  == B64 + B32 - 1;       m_src_emax == 2 * B64; }
        (m_f2f_pair == F2F_D2H) -> { m_dst_snmin == B64 + 1 - B16 - M16; m_dst_nmin == B64 + 1 - B16;
                                     m_dst_nmax  == B64 + B16 - 1;       m_src_emax == 2 * B64; }
        (m_f2f_pair == F2F_S2H) -> { m_dst_snmin == B32 + 1 - B16 - M16; m_dst_nmin == B32 + 1 - B16;
                                     m_dst_nmax  == B32 + B16 - 1;       m_src_emax == 2 * B32; }
        !(m_f2f_pair inside {F2F_D2S, F2F_D2H, F2F_S2H}) ->
                                   { m_dst_snmin == 0; m_dst_nmin == 0; m_dst_nmax == 0; m_src_emax == 0; }
    }

    // --- fp_op_type[0] per F2F stimulus --------------------------------------
    constraint f2f_fp_type_c {
        (m_conv_stim == F2F_BELLOW_SUBNORM) -> m_fp_op_type[0] inside {NORMAL, SUBNORMAL};
        (m_conv_stim == F2F_LOW_SUBNORM_UF) -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_SUBNORM_NORM)   -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_LOW_NORMAL)     -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_NARROW_NORMAL)  -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_HIGH_NORMAL)    -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_NARROW_OF)      -> m_fp_op_type[0] == NORMAL;
        (m_conv_stim == F2F_NAN_INF)        -> m_fp_op_type[0] inside {INF, QNAN, SNAN};
    }

    // --- Source exponent zones for narrowing ---------------------------------
    // fp_exp_c in parent handles INF/NaN exponents; only NORMAL ranges below.
    constraint f2f_narrow_exp_c {
        if (m_operation == FCVT_F2F && m_f2f_pair inside {F2F_D2S, F2F_D2H, F2F_S2H} &&
            m_conv_stim inside {F2F_BELLOW_SUBNORM, F2F_LOW_SUBNORM_UF, F2F_SUBNORM_NORM,
                                F2F_LOW_NORMAL, F2F_NARROW_NORMAL, F2F_HIGH_NORMAL,
                                F2F_NARROW_OF}) {
            (m_imm == FMT_FP64) -> m_fp_double_operands[0].exponent == m_f2f_src_exp;
            (m_imm == FMT_FP32) -> m_fp_single_operands[0].exponent == m_f2f_src_exp;

            (m_conv_stim == F2F_BELLOW_SUBNORM) -> m_f2f_src_exp inside {[0 : m_dst_snmin - 2]};
            (m_conv_stim == F2F_LOW_SUBNORM_UF) -> m_f2f_src_exp inside {[m_dst_snmin - 1 : m_dst_snmin + 1]};
            (m_conv_stim == F2F_SUBNORM_NORM)   -> m_f2f_src_exp inside {[m_dst_snmin + 2 : m_dst_nmin - 2]};
            (m_conv_stim == F2F_LOW_NORMAL)     -> m_f2f_src_exp inside {[m_dst_nmin - 1  : m_dst_nmin + 1]};
            (m_conv_stim == F2F_NARROW_NORMAL)  -> m_f2f_src_exp inside {[m_dst_nmin + 2  : m_dst_nmax - 2]};
            (m_conv_stim == F2F_HIGH_NORMAL)    -> m_f2f_src_exp inside {[m_dst_nmax - 1  : m_dst_nmax + 1]};
            (m_conv_stim == F2F_NARROW_OF)      -> m_f2f_src_exp inside {[m_dst_nmax + 2  : m_src_emax]};
        } else {
            m_f2f_src_exp == 0;
        }
    }

    // =========================================================================
    // post_randomize override
    // =========================================================================
    // For FCVT_I2F the operand is a raw integer; NaN-boxing its bits would
    // corrupt INT_MIN, UINT_MAX, etc.  Skip the parent boxing in that case.
    function void post_randomize();
        if (m_operation == FCVT_I2F)
            return;
        super.post_randomize();
    endfunction

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "fpu_txn_conv");
        super.new(name);
    endfunction : new

endclass : fpu_txn_conv
