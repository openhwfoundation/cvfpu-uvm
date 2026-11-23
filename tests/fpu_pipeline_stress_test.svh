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
 *  Creation Date : October, 2026
 *  Description   : Fully-random, sustained back-to-back traffic with frequent
 *                  flush and reset events, deliberately timed to coincide with
 *                  in-flight transactions at every reachable pipeline depth
 *                  (closes the Pipeline Behavior Coverage flush-vs-depth and
 *                  reset-during-pipeline bins).
 *  History       :
 */

class fpu_pipeline_stress_test extends base_test;

    `uvm_component_utils(fpu_pipeline_stress_test)

    fpu_random_op_bp_seq  m_seq;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction: new

    // -------------------------------------------------------------------------
    // Pre Main Phase
    // -------------------------------------------------------------------------
    virtual task pre_main_phase(uvm_phase phase);

      // Sustained back-to-back traffic (m_delay==0), fully random op/format
      m_seq = fpu_random_op_bp_seq::type_id::create("seq");
      if(!$cast(base_sequence, m_seq)) `uvm_fatal("CAST FAILED", "cannot cast base seqence");

      super.pre_main_phase(phase);

    endtask: pre_main_phase

    // -------------------------------------------------------------------------
    // End of elaboration phase
    // -------------------------------------------------------------------------
    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);

      // super already randomized env.m_fpu_top_cfg and set up the default
      // (single-pulse) flush/reset config; force the fields/settings that
      // matter for this test instead of leaving them to randomize().
      env.m_fpu_top_cfg.m_flush_on_the_fly = 1;
      env.m_fpu_top_cfg.m_reset_on_the_fly = 1;

      env.m_flush_cfg.set_pulse_enable(1);
      env.m_flush_cfg.set_pulse_clock_based(1);
      env.m_flush_cfg.set_pulse_width(1);
      env.m_flush_cfg.set_pulse_period(11);  // not a clean multiple of the 1-3 cycle pipeline depths
      env.m_flush_cfg.set_pulse_num(50);     // re-arms FLUSH_THREAD for 50 restarts (base_test.svh)

      // super's own call saw the old (possibly 0) m_reset_on_the_fly value
      env.m_reset_driver.set_num_reset($urandom_range(10, 5));

      `uvm_info("TOP CFG", $sformatf("%s", env.m_fpu_top_cfg.convert2string()), UVM_DEBUG)
    endfunction: end_of_elaboration_phase

endclass: fpu_pipeline_stress_test
