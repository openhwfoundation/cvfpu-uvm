/*
 *  Copyright (c) 2026 Eclipse Foundation
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */
/*
 *  Authors       : Ihsane TAHIR
 *  Creation Date : April, 2026
 *  Description   : 
 *  History       :
 */

class fpu_noncomput_cov extends uvm_subscriber #(fpu_obs_txn);
    `uvm_component_utils(fpu_noncomput_cov)

     // -------------------------------------------------------------------------
    // CG_CMP - Compare Operations (FEQ, FLT, FLE)
    // -------------------------------------------------------------------------
    covergroup cg_compare with function sample(
        logic [1:0]            op,        // 0=FLE, 1=FLT, 2=FEQ
        fpnew_pkg::classmask_e op1_class,
        fpnew_pkg::classmask_e op2_class,
        logic [1:0]            fmt,       // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic [4:0]            flags,
        logic                  result
    );
        option.per_instance = 1;

        cp_op:  coverpoint op  { 
            bins cmp_leq = {2'b00}; // FLE
            bins cmp_lt  = {2'b01}; // FLT
            bins cmp_eq  = {2'b10}; // FEQ
        }

        cp_fmt: coverpoint fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_op1_class: coverpoint op1_class; // Covers all 10 classes
        cp_op2_class: coverpoint op2_class; // Covers all 10 classes

        cp_flags: coverpoint flags {
            bins NO_EXCEPTION = {'h0};
            wildcard bins NV = {5'b1????}; // Bit 4: Invalid Operation
        }

        cp_result: coverpoint result;

        cx_fcmp_op_x_res: cross cp_op, cp_result, cp_fmt;

        cx_fcmp_op1_x_op2: cross cp_op, cp_op1_class, cp_op2_class, cp_fmt;
        
    endgroup

    // -------------------------------------------------------------------------
    // CG_CMP - Classify Operation (FCLASS)
    // -------------------------------------------------------------------------
    covergroup cg_classify with function sample(
        fpnew_pkg::classmask_e op_class, // Inferred from input operand classification
        logic [1:0]            fmt,      // 2'b00=FP32, 2'b01=FP64, 2'b10=FP16
        logic [9:0]            result
    );
        option.per_instance = 1;

        cp_op_class: coverpoint op_class;

        cp_res_class: coverpoint result {
            bins neg_inf     = {10'b00_0000_0001};  // bit 0
            bins neg_normal  = {10'b00_0000_0010};  // bit 1
            bins neg_subnorm = {10'b00_0000_0100};  // bit 2
            bins neg_zero    = {10'b00_0000_1000};  // bit 3
            bins pos_zero    = {10'b00_0001_0000};  // bit 4
            bins pos_subnorm = {10'b00_0010_0000};  // bit 5
            bins pos_normal  = {10'b00_0100_0000};  // bit 6
            bins pos_inf     = {10'b00_1000_0000};  // bit 7
            bins snan        = {10'b01_0000_0000};  // bit 8
            bins qnan        = {10'b10_0000_0000};  // bit 9
            illegal_bins multi_bit = default;        // only one bit legal at a time
        }

        cp_fmt: coverpoint fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        // Full cross: also sweep rounding modes (verifies rm is irrelevant)
        cx_fclass_x_fmt_x_rnd: cross cp_op_class, cp_fmt;

    endgroup : cg_classify

    // -------------------------------------------------------------------------
    // CG_MV - Move Operations
    // -------------------------------------------------------------------------
    covergroup cg_move_f2x with function sample(
        fpnew_pkg::classmask_e     op_class,
        logic [1:0]                fmt,
        fpu_common_pkg::nan_kind_e nan_kind,
        logic                      boxed
    );
        option.per_instance = 1;

        cp_op_class: coverpoint op_class;
        cp_fmt:      coverpoint fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_nan_kind: coverpoint nan_kind {
            bins canonical_qnan = {fpu_common_pkg::CANONICAL_QNAN};
            bins noncanon_qnan  = {fpu_common_pkg::NONCANON_QNAN};
            bins snan           = {fpu_common_pkg::SNAN_KIND};
        }

        // Transfers are exempt from the NaN-box check, so an improperly boxed
        // source must still move its low bits unchanged.
        cp_boxed: coverpoint boxed {
            bins properly_boxed   = {1'b1};
            bins improperly_boxed = {1'b0};
        }

        cx_op_class_x_fmt: cross cp_op_class, cp_fmt;
        cx_nan_kind_x_fmt: cross cp_nan_kind, cp_fmt;
        cx_boxed_x_fmt:    cross cp_boxed, cp_fmt {
            ignore_bins fp64_always_boxed = binsof(cp_boxed.improperly_boxed) && binsof(cp_fmt.fp64);
        }
    endgroup

    covergroup cg_move_x2f with function sample(
        fpnew_pkg::classmask_e     op_class,
        logic [1:0]                fmt,
        fpu_common_pkg::nan_kind_e nan_kind,
        logic [1:0]                src_upper   // 0=zero, 1=all ones, 2=other, 3=n/a (FP64)
    );
        option.per_instance = 1;

        cp_op_class: coverpoint op_class;
        cp_fmt:      coverpoint fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_nan_kind: coverpoint nan_kind {
            bins canonical_qnan = {fpu_common_pkg::CANONICAL_QNAN};
            bins noncanon_qnan  = {fpu_common_pkg::NONCANON_QNAN};
            bins snan           = {fpu_common_pkg::SNAN_KIND};
        }

        // Upper integer bits must be ignored and replaced by the NaN box.
        cp_src_upper: coverpoint src_upper {
            bins zero     = {2'd0};
            bins all_ones = {2'd1};
            bins other    = {2'd2};
            ignore_bins na = {2'd3};
        }

        cx_op_class_x_fmt:   cross cp_op_class, cp_fmt;
        cx_nan_kind_x_fmt:   cross cp_nan_kind, cp_fmt;
        cx_src_upper_x_fmt:  cross cp_src_upper, cp_fmt {
            ignore_bins fp64 = binsof(cp_fmt.fp64);
        }
    endgroup

    // -------------------------------------------------------------------------
    // CG_MV - Sign Injection Operations (FSGNJ, FSGNJN, FSGNJX)
    // -------------------------------------------------------------------------
    covergroup cg_sign_injection with function sample(
        logic [1:0]            op,
        logic [1:0]            fmt,
        fpnew_pkg::classmask_e op_class,
        logic                  op2_sign,
        logic                  same_operands,
        fpu_common_pkg::nan_kind_e nan_kind
    );
        option.per_instance = 1;

        cp_op_class: coverpoint op_class;

        // rs1 == rs2 is how FMV/FNEG/FABS are encoded.
        cp_same: coverpoint same_operands {
            bins pseudo_op = {1'b1};
        }

        cp_nan_kind: coverpoint nan_kind {
            bins canonical_qnan = {fpu_common_pkg::CANONICAL_QNAN};
            bins noncanon_qnan  = {fpu_common_pkg::NONCANON_QNAN};
            bins snan           = {fpu_common_pkg::SNAN_KIND};
        }

        cp_fsgn_op: coverpoint op {
            bins        fsgnj  = {2'b00};
            bins        fsgnjn = {2'b01};
            bins        fsgnjx = {2'b10};
            ignore_bins others = {2'b11};
        }

        cp_fmt:  coverpoint fmt {
            bins fp32 = {2'b00};
            bins fp64 = {2'b01};
            bins fp16 = {2'b10};
        }

        cp_op2_sign: coverpoint op2_sign;
        
        // Cross all coverroups
        cx_fsgn_x_sign_x_fmt: cross cp_fsgn_op, cp_op_class, cp_op2_sign, cp_fmt;
        cx_pseudo_op:         cross cp_fsgn_op, cp_same, cp_fmt;
        cx_fsgn_x_nan_kind:   cross cp_fsgn_op, cp_nan_kind;
    endgroup

    // Constructor
    function new(string name = "fpu_noncomput_cov", uvm_component parent = null);
        super.new(name, parent);
        cg_compare        = new();
        cg_classify       = new();
        cg_move_f2x       = new();
        cg_move_x2f       = new();
        cg_sign_injection = new();
    endfunction : new

    // =========================================================================
    // UVM subscriber write() — routes each observed txn to the right covergroup
    // =========================================================================
    function void write(fpu_obs_txn t);
        case (t.m_operation)
            // -----------------------------------------------------------------
            FCMP: begin
                cg_compare.sample(
                    t.m_rm[1:0], // 0=FLE, 1=FLT, 2=FEQ
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt),
                    fpu_common_pkg::classify_operand(t.m_operand_b, t.m_fmt),
                    t.m_fmt,
                    t.status_o,
                    t.result_o[0]
                );
            end

            FCLASS: begin
                cg_classify.sample(
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt),
                    t.m_fmt,
                    t.result_o[9:0]
                );
            end

            FSGNJ: begin
                cg_sign_injection.sample(
                    t.m_rm[1:0], // 0=FSGNJ, 1=FSGNJN, 2=FSGNJX
                    t.m_fmt,
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt),
                    fpu_common_pkg::get_operand_sign(t.m_operand_b, t.m_fmt),
                    t.m_operand_a == t.m_operand_b,
                    fpu_common_pkg::nan_kind(t.m_operand_a, t.m_fmt)
                );
            end

            FMV_F2X: begin
                cg_move_f2x.sample(
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt, 1'b0),
                    t.m_fmt,
                    fpu_common_pkg::nan_kind(t.m_operand_a, t.m_fmt, 1'b0),
                    fpu_common_pkg::operand_is_boxed(t.m_operand_a, t.m_fmt)
                );
            end

            FMV_X2F: begin
                cg_move_x2f.sample(
                    fpu_common_pkg::classify_operand(t.m_operand_a, t.m_fmt, 1'b0),
                    t.m_fmt,
                    fpu_common_pkg::nan_kind(t.m_operand_a, t.m_fmt, 1'b0),
                    x2f_src_upper(t.m_operand_a, t.m_fmt)
                );
            end
        endcase
    endfunction : write

    function logic [1:0] x2f_src_upper(logic [CVA6Cfg.XLEN-1:0] value, logic [1:0] fmt);
        int unsigned width = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(fmt));
        logic [CVA6Cfg.XLEN-1:0] upper;
        if (width >= CVA6Cfg.XLEN) return 2'd3;
        upper = value >> width;
        if (upper == '0) return 2'd0;
        if (upper == ({CVA6Cfg.XLEN{1'b1}} >> width)) return 2'd1;
        return 2'd2;
    endfunction : x2f_src_upper

endclass : fpu_noncomput_cov