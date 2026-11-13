/*
 *  Copyright (c) 2025 CEA*
 *  *Commissariat a l'Energie Atomique et aux Energies Alternatives (CEA)
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 *  Licensed under the Solderpad Hardware License v 2.1 (the “License”); you
 *  may not use this file except in compliance with the License, or, at your
 *  option, the Apache License version 2.0. You may obtain a copy of the
 *  License at
 *
 *  https://solderpad.org/licenses/SHL-2.1/
 *
 *  Unless required by applicable law or agreed to in writing, any work
 *  distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 *  License for the specific language governing permissions and limitations
 *  under the License.
 */
/*
 *  Authors       : Ihsane TAHIR
 *  Creation Date : March, 2025
 *  Description   : Top module of the CVFPU UVM testbench
 *  History       :
 */


module top;


    timeunit 1ns;
    timeprecision 1ps;

    // -----------------------------------------------------------------
    // Import/Include
    // -----------------------------------------------------------------
    `include "uvm_macros.svh"

    import uvm_pkg::*;
    import fpu_common_pkg::*;
    import fpu_test_pkg::*;
    import bp_driver_pkg::*;

    typedef struct packed {
        logic [CVA6Cfg.FLen-1:0]          result;
        fpnew_pkg::status_t               status;
        logic [CVA6Cfg.TRANS_ID_BITS-1:0] tag;
    } output_t;

    // -----------------------------------------------------------------
    // Clock/Reset signals
    // -----------------------------------------------------------------
    bit   reset;
    bit   post_shutdown_phase;
    logic clk;
    logic rst_n;

   // -----------------------------------------------------------------
   // Interfaces
   // ----------------------------------------------------------------- 
    xrtl_clock_vif clock_if( .clock(clk));

    xrtl_reset_vif #(1'b1,50,0) reset_if (.clk(clk),
                                           .reset(reset),
                                           .reset_n(rst_n), 
                                           .post_shutdown_phase(post_shutdown_phase));
    
    fpu_if   fpu_vif         (.clk_i( clk ), .rst_ni( rst_n ) );
    pulse_if flush_vif       (.clk  ( clk ), .rstn  ( rst_n ) );
    bp_vif #(1) req_bp_vif   ( .clk ( clk ), .rstn  ( rst_n ) );

   // -----------------------------------------------------------------
   // DUT: CVFPU wrapper for CVA6
   // -----------------------------------------------------------------
    fpu_wrap # (
        .CVA6Cfg   ( CVA6Cfg   ),
        .fu_data_t ( fu_data_t ),
        .exception_t (exception_t)
    ) dut (
        .clk_i           ( clk                    ),
        .rst_ni          ( rst_n                  ),
        .flush_i         ( flush_vif.m_pulse_out  ),
        .fpu_valid_i     ( fpu_vif.fpu_valid_i    ),
        .fpu_ready_o     ( fpu_vif.fpu_ready_o    ),
        .fu_data_i       ( fpu_vif.fu_data_i      ),
        .fpu_fmt_i       ( fpu_vif.fpu_fmt_i      ),
        .fpu_rm_i        ( fpu_vif.fpu_rm_i       ),
        .fpu_frm_i       ( fpu_vif.fpu_frm_i      ),
        .fpu_prec_i      ( fpu_vif.fpu_prec_i     ),
        .fpu_trans_id_o  ( fpu_vif.fpu_trans_id_o ),
        .result_o        ( fpu_vif.result_o       ),
        .fpu_valid_o     ( fpu_vif.fpu_valid_o    ),
        .fpu_exception_o ( fpu_vif.fpu_exception_o ),
        .fpu_early_valid_o ( fpu_vif.fpu_early_valid_o )
    );

    //Binding with SVA using implicit port connection
    bind fpu_wrap cvfpu_sva#(
        .CVA6Cfg(CVA6Cfg),
        .fu_data_t(fu_data_t),
        .exception_t(exception_t)
    ) sva(.*);

    bind dut.fpu_gen.i_fpnew_bulk.i_arbiter cvfpu_rsp_arb_sva#(
        .NumIn(fpnew_pkg::NUM_OPGROUPS),
        .DataType(output_t)
    ) rsp_arb_sva(.*);

`ifdef FPU_FUNC_COV_EN
    bind fpu_wrap cvfpu_pipeline_sva#(
        .CVA6Cfg(CVA6Cfg),
        .fu_data_t(fu_data_t)
    ) pipeline_sva(.*);
    
    // Regs paramaters are hardwired, if any changes in the op-groups pipeline stages occur, these values need to be updated accordingly.
    // ADDMUL (fpnew_fma), PARALLEL: one instance per active format (FP32,
    // FP64, FP16 — FP8/FP16ALT disabled in this config).
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[0].i_opgroup_block.gen_parallel_slices[0].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_fma
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(1), .NumOutRegs(0)) stage_occ_addmul_fp32_sva(.*);
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[0].i_opgroup_block.gen_parallel_slices[1].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_fma
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(1), .NumOutRegs(1)) stage_occ_addmul_fp64_sva(.*);
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[0].i_opgroup_block.gen_parallel_slices[2].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_fma
        cvfpu_stage_occupancy_sva#(.NumInpRegs(0), .NumMidRegs(1), .NumOutRegs(0)) stage_occ_addmul_fp16_sva(.*);

    // NONCOMP (fpnew_noncomp), PARALLEL: one instance per active format.
    // fpnew_noncomp has no mid_pipe_valid_q signal at all (no mid stage), so
    // that port can't be found by (.*) — tie it off explicitly
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[2].i_opgroup_block.gen_parallel_slices[0].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_noncomp
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(0), .NumOutRegs(0)) stage_occ_noncomp_fp32_sva(.mid_pipe_valid_q('0), .*);
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[2].i_opgroup_block.gen_parallel_slices[1].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_noncomp
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(0), .NumOutRegs(0)) stage_occ_noncomp_fp64_sva(.mid_pipe_valid_q('0), .*);
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[2].i_opgroup_block.gen_parallel_slices[2].active_format.i_fmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_noncomp
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(0), .NumOutRegs(0)) stage_occ_noncomp_fp16_sva(.mid_pipe_valid_q('0), .*);

    // CONV (fpnew_cast_multi), MERGED: one shared instance for all formats.
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[3].i_opgroup_block.gen_merged_slice.i_multifmt_slice.gen_num_lanes[0].active_lane.lane_instance.i_fpnew_cast_multi
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(1), .NumOutRegs(0)) stage_occ_conv_sva(.*);

    // DIVSQRT (fpnew_divsqrt_th_64_multi), MERGED: one shared instance for
    // all formats
    bind dut.fpu_gen.i_fpnew_bulk.gen_operation_groups[1].i_opgroup_block.gen_merged_slice.i_multifmt_slice.gen_num_lanes[0].active_lane.lane_instance.gen_thmulti_c910_divsqrt.i_fpnew_divsqrt_th_64_c910
        cvfpu_stage_occupancy_sva#(.NumInpRegs(1), .NumMidRegs(0), .NumOutRegs(1)) stage_occ_divsqrt_sva(.mid_pipe_valid_q('0), .*);
`endif

    initial begin
        uvm_config_db#(virtual fpu_if)::set(uvm_root::get( ) , "*" , "fpu_vif", fpu_vif);
        uvm_config_db#(virtual pulse_if)::set(uvm_root::get(), "*", "flush_driver", flush_vif );
        uvm_config_db#(virtual xrtl_clock_vif)::set(uvm_root::get( ) , "*" , "clk_if", clock_if);
        uvm_config_db#(virtual bp_vif #(1))::set(uvm_root::get(), "*", "req_bp_agent", req_bp_vif);

        uvm_config_db #(virtual xrtl_clock_vif)::set(uvm_root::get() , "*" , "clock_driver" , clock_if);
        uvm_config_db #( virtual xrtl_reset_vif #( 1'b1,50,0) )::set(uvm_root::get(), "*", "reset_driver", reset_if );
        run_test();
    end

endmodule