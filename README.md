# CVFPU UVM Testbench

## 1. Project Overview
This repository contains a UVM Verification Environment for the [CVFPU](https://github.com/openhwgroup/cvfpu.git). DUT is the CVA6 wrapper of the floating-point unit.

## 2. Testbench Architecture

![CVA6 Tile Platform](./images/cvfpu_uvm_tb_archi.png)

## 3. Project Structure
The repository is organised as follows:
- **docs/testplan/** Contains the testplan for the CVFPU UVM environment
- **env/** Contains UVM environment, scoreboard and top configuration classes
- **fpu_agent/** Contains UVM agent, driver, sequencer, monitor, interface, sequences and transaction item
- **fpu_common/** Contains package used accross UVM testbench
- **modules/** Contains dependencies of the project: [cva6](https://github.com/openhwgroup/cva6.git) and [core-v-verif](https://github.com/openhwgroup/core-v-verif.git) repositories. Both are included as git submodules.
- **ref_model_csim/** Contains C++ reference model as well as SystemVerilog wrapper
- **simu/** Contains regression test list and yaml files needed to run simulation and regression scripts. It also holds log files
- **tests/** Contains UVM test classes
- **top/** Contains top-level testbench file
- **scripts/** Contains `scan_logs.pl` perl script for parsing log files, reporting errors and warnings, and generating summary reports.

## 4. Getting started
### 4.1 Environment Setup
Before building or running the project, you must configure your environment variables. The testbench works with QuestaSim simulator, Xcelium and VCS so ensure the `QUESTA_PATH`, `XLM_PATH` or `VCS_PATH` variable is set to your installation directory.

**tcsh**
```
setenv QUESTA_PATH <questa_path> 
   # ex: setenv QUESTA_PATH <path_to_your_install>/questasim/2025.1
```
**bash**
```
export QUESTA_PATH=<questa_path>
```
We also provide two scripts to setup the project environment, source the one that matches the shell of the machine.

| Shell Type      | Command to Run         |
| --------------- | -----------------------|
| **csh/tcsh**    | `source setup_env.csh <tool>` |
| **bash/zsh/sh** | `source setup_env.sh <tool>`  |

where <tool> can be `questa`, `xcelium` or `vcs`.

> **Note:**
> The first part of these scripts performs a git update of the submodules. Check the correctness of the remote url in the `.gitmodules` file

Some of the testbench utilities (compilation, simulation and regression scripts) use Python. Dependencies are listed in `requirements.txt`.

### 4.2. Compile C++ Reference Model
Build the shared library `refmodel_csim_lib.so` used in the UVM testbench via DPI.

#### Dependencies
The following dependencies need to be installed in the system:

- **Bender** a dependency management tool for HW design projects. See https://github.com/pulp-platform/bender.git for information ans installation guide.
- **GMP** (GNU Multiple Precision Arithmetic Library).
- **MPFR** (Multiple Precision Floating-Point Reliable Library): Section [*2.1 How to Install*](https://www.mpfr.org/mpfr-current/mpfr.html) details the steps to follow to install the library, use preferably version **4.2.2**.

Set GMP/MPFR directory path variables in the environment.

**tcsh**
```
setenv GMP_DIR <gmp_dir_absolute_path>
setenv MPFR_DIR <mpfr_dir_absolute_path>
```
**bash**
```
export GMP_DIR=<gmp_dir_absolute_path>
export MPFR_DIR=<mpfr_dir_absolute_path>
```

#### Compilation
```
cd ./ref_model_csim/cpp/
make TOOL=<tool>
```

### 4.2. Build and run simulation 
#### Compile testbench
```
cd ${PROJECT_DIR}/simu/
python3 ${SCRIPTS_DIR}/compile.py --yaml sim_<tool>.yaml
```
#### Run a test

The number of transactions is set by the variable `+NB_TXNS` (passed as simulation option) in the `sim_<tool>.yaml` file.

Functional coverage (UVM covergroups) is collected by default. To disable it for a run, add `+FPU_FUNC_COV_DIS` to the simulation options in the `sim_<tool>.yaml` file.
```
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_<tool>.yaml --test_name <TEST_NAME> --seed <SEED> --debug <VERBOSITY>
```
For example
```
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_questa.yaml --test_name fpu_random_test --seed 1 --debug UVM_LOW
```
Simulation logs can be found in the `output/` folder.

The test runs in batch mode automatically but it can be run also using the GUI of the used tool.

For example
```
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_xcelium.yaml --test_name fpu_random_test --seed 1 --debug UVM_LOW --batch 0
```
in this case the simulation will be managed by Simvision.

It is also possible to create a post-simulation debug database with the `--dump` option and open the saved dataset with the GUI subsequently. It is useful especially in batch mode but it can be used also while running the simulation with the GUI

```
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_<tool>.yaml --test_name fpu_random_test --seed 1 --debug UVM_LOW --dump 1
```
will create a database file in the `output/<tool>_db/` folder that can be used later by mean of the command:
```
python3 ${SCRIPTS_DIR}/post_proc.py --tool <tool> --db_file <db_file_path>
```
> **Note:**
>If VCS is the selected tool, the `VERDI_HOME` path must be configured as an environment variable, for a bash shell:
```
export VERDI_HOME=/path/to/Verdi
```

#### Run a regression
The regression suite is defined in the `simu/fpu_reg_list` file. Each line in this file specifies:
- **Test Name:** The UVM test class to run.
- **Number of Runs:** How many times to run that test, each one has a different randomly generated seed

Edit this file to decrease/increase the number of runs.

Check the `testplan` for more details on the available tests.
```
python3 ${SCRIPTS_DIR}/run_reg.py --yaml sim_<tool>.yaml --nthreads 3 --reg_list fpu_reg_list
```
Regression logs can be found in the `regression/` folder. To parse through them, run the following script which will return result of the tests with either PASS or FAIL.
```
scan_logs.pl -nowarn --pat ${PROJECT_DIR}/scripts/patterns/sim_patterns.pat --waiver ${PROJECT_DIR}/scripts/patterns/sim_waivers.pat regression/fpu_*_test_*.log
```
The regression tests run automatically in batch mode and with the dump option enabled, so that the created database files can be found in the `regression/<tool>_db/` folder and used by mean of the `post_proc` command 

#### Code coverage (Questasim only)

Coverage is opt-in and flows in four stages: instrument + collect, merge, waive (optional), report. All of the coverage scripts and options are documented in full in [`sim_cmd`'s own README](modules/core-v-verif/lib/cv_dv_utils/python/sim_cmd/README.md); this section covers the common project workflow.

The functional coverage model and the SVA cover properties are always compiled; no compile-time define is needed. Covergroup sampling can be turned off at run time with `+FPU_FUNC_COV_DIS` (see [Run a test](#run-a-test)), while the SVA cover properties remain active.

**Single test**, instrumented for branch/condition/statement/FSM coverage and scoped to the DUT:
```
python3 ${SCRIPTS_DIR}/compile.py --yaml sim_questa.yaml --cover 1 --cover_types bcfs --cover_instance /top/dut
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_questa.yaml --test_name fpu_random_test --seed 1 --cover 1
```
The UCDB is saved to `output/coverage/fpu_random_test_1.ucdb`.

**Regression**, with an automatic merge and HTML report once every test finishes:
```
python3 ${SCRIPTS_DIR}/run_reg.py --yaml sim_questa.yaml --nthreads 3 --reg_list fpu_reg_list \
    --cover 1 --cover_types bcfs --cover_instance /top/dut --cover_merge 1 --cover_report 1
```
This produces `regression/coverage/merged.ucdb` and an HTML report under `regression/cov_report/`.

**Applying waivers**: this project's coverage exclusions (with rationale) live in `simu/tools/vsim/exclude.do`. To fold them into the merged UCDB, keeping the pre-waiver database untouched, pass `--cover_excl_file` alongside `--cover_merge 1`:
```
python3 ${SCRIPTS_DIR}/run_reg.py --yaml sim_questa.yaml --nthreads 3 --reg_list fpu_reg_list \
    --cover 1 --cover_merge 1 --cover_excl_file ${PROJECT_DIR}/simu/tools/vsim/exclude.do --cover_report 1
```
This produces `regression/coverage/merged_excluded.ucdb` in addition to the pre-waiver `merged.ucdb`.

An exclusion file is only ever applied when explicitly passed on the command line -- there is no default exclusion file baked into the scripts, and any new exclusions must be reviewed and approved before being added to `simu/tools/vsim/exclude.do`.

**Standalone merge/report**, e.g. to regenerate a report from an already-merged UCDB, or to get a holes-only or metrics summary instead of the full HTML report:
```
python3 ${SCRIPTS_DIR}/cov_merge.py --outdir regression --excl_file ${PROJECT_DIR}/simu/tools/vsim/exclude.do
python3 ${SCRIPTS_DIR}/cov_report.py --ucdb regression/coverage/merged_excluded.ucdb --cover_types bcfs --instance /top/dut --report_type holes --holes_threshold 100
python3 ${SCRIPTS_DIR}/cov_report.py --ucdb regression/coverage/merged_excluded.ucdb --cover_types bcfs --instance /top/dut --report_type metrics
```

### 4.2. Known Limitations
* The current verification environment targets the CVA6 core exclusively.
* `RMM`, `ROD`, and `DYN` rounding modes have not been fully verified.
* Vector floating-point operations are not supported by the current testbench.
* Only `FP32`, `FP64`, and `FP16` formats are thoroughly tested. Other formats are verified only within `F2F` (float-to-float) conversion operations.
* For `F2I` (float-to-integer) and `I2F` (integer-to-float) operations, only `INT32` and `INT64` integer formats are tested.

### 4.3 Adding a new test
For users who are not familiar with UVM, here are some simple steps to follow to create a new test to verify a new feature.

---
#### Step 1: Create a New Sequence
A **sequence** generates the transactions (stimulus) that will be driven to the DUT.

Example: create a new sequence class in `fpu_sequences.svh` file:

```systemverilog
class my_feature_seq extends fpu_base_sequence;

  `uvm_object_utils(my_feature_seq)

  fpu_txn item;

  function new(string name = "my_feature_seq");
    super.new(name);
  endfunction

  virtual task body();
    super.body();

    item = fpu_txn::type_id::create("my_feature_item");

    for (int i = 0; i < num_txn; i++) begin
      // Randomize or constrain the transaction to target your feature
      if (!item.randomize() with {
          m_operation == FDIV;        // force divide operation
          m_fmt       == FP32;        // force single-precision format
          m_operand_a == opA;
          m_operand_b == opB;
          m_imm       == imm;
          m_rm        == 0;      // force round to nearest, ties to even
      }) begin
        `uvm_fatal("SEQ", "Randomization failed");
      end

      start_item(item);
      finish_item(item);
    end
  endtask
endclass
```
You can change constraints to target the feature you want to verify. Sequence item fields to randomize are defined in `fpu_txn.svh` file.

---
#### Step 2: Create a New Test Class

The test class instantiates and starts your new sequence.
Create a new file under `tests/` called `my_feature_test.svh`:

```systemverilog
class my_feature_test extends base_test;

  `uvm_component_utils(my_feature_test)

  my_feature_seq m_seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task pre_main_phase(uvm_phase phase);
    m_seq = my_feature_seq::type_id::create("seq");
    if(!$cast(base_sequence, m_seq)) 
      `uvm_fatal("CAST FAILED", "Cannot cast base sequence");

    super.pre_main_phase(phase);
  endtask
endclass
```
---
#### Step3: Register the Test
Add the new test to the `fpu_test_pkg.sv` file.
```systemverilog
  `include "my_feature_test.svh"
```
---
#### Step 4: Run the Test
From the `simu/` directory, compile and run the simulation by following directions detailed in section [4.2](#42-known-limitations).

As an example:
```
python3 ${SCRIPTS_DIR}/compile.py --yaml sim_xcelium.yaml
python3 ${SCRIPTS_DIR}/run_test.py --yaml sim_xcelium.yaml --test_name my_feature_test --seed 1 --debug UVM_LOW --dump 1
```
---

#### Step 5: Check Results
Review the log file `my_feature_test_1.log` located in the `output/` directory for `UVM_ERROR` messages. You can run the `scan_logs` script to help parse through the file for errors and warnings.

Open the waveform file if needed to inspect DUT behavior.
```
python3 ${SCRIPTS_DIR}/post_proc.py --tool xcelium --db_file ./output/xlm_db/my_feature_test_1.shm 
```
