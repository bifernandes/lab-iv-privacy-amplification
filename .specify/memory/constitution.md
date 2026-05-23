<!--
## Sync Impact Report

**Version Change**: [template — unversioned] → 1.0.0

**Modified Principles**: N/A — initial ratification (all placeholders replaced)

**Added Sections**:
- Core Principles (5 principles)
- Hardware Platform Constraints
- Development & Verification Workflow
- Governance

**Removed Sections**: None

**Templates Updated**:
- ✅ `.specify/memory/constitution.md` — written now
- ✅ `.specify/templates/plan-template.md` — Constitution Check gates are generic; remain applicable
- ✅ `.specify/templates/spec-template.md` — FR/NFR structure aligns with RF/RNF schema used by this project
- ✅ `.specify/templates/tasks-template.md` — task phases (setup → foundational → stories → polish) map directly to module pipeline

**Deferred TODOs**: None
-->

# Privacy Amplification FPGA Constitution

## Core Principles

### I. FPGA-First — Synthesizable Verilog Only (NON-NEGOTIABLE)

Every module MUST be written in synthesizable Verilog RTL targeting the
Altera DE2-115 Cyclone IV EP4CE115F29C7.

- Behavioral constructs (initial blocks, delays `#N`, `$display` in non-TB
  code, dynamic allocation) are FORBIDDEN in synthesizable source files.
- Altera-specific IP cores (altsyncram, altpll, altsyncfifo) MUST be used for
  on-chip memory and clock generation; instantiation MUST use the `.qip`-backed
  megafunction wrappers produced by Quartus MegaWizard / IP Catalog.
- All Verilog source files MUST compile cleanly in Quartus Prime Lite without
  errors or critical warnings related to latch inference, undriven outputs,
  or incomplete sensitivity lists.
- Testbench files (`*_tb.v`, `top_mem_tb.v`) MAY use non-synthesizable
  constructs; they MUST be clearly separated from synthesizable sources and
  excluded from the synthesis file set in `.qsf`.

### II. Toeplitz Universal Hash — Reference-Model Parity (NON-NEGOTIABLE)

The hash engine MUST implement Toeplitz-matrix multiplication exactly as
defined by the Python reference model (`high_level_simulation/compression_model.py`
using `scipy.linalg.toeplitz`).

- A Toeplitz matrix T of dimension L×N is fully specified by its first row and
  first column (N+L−1 seed bits total). Entry T[i,j] = seed[i−j] where the
  index wraps via the seed vector.
- RTL output bits MUST be bit-identical to Python reference output for all
  test vectors before any commit to `main`.
- Hankel or other structured-matrix variants are EXPLICITLY PROHIBITED as
  drop-in replacements; any change to the hash structure requires updating
  the reference model first and re-validating all test vectors.
- The seed (matrix_window of W+P−1 bits) MUST be loaded from an external
  source (Seed Generator / Loader module); hardcoded seeds are allowed only
  in testbenches.

### III. Performance Budget — Timing Closure Before Merge

The system MUST meet all of the following before a feature branch is merged:

- **Frequency**: Fmax ≥ 100 MHz on Cyclone IV EP4CE115F29C7 (Quartus
  TimeQuest Timing Analyzer report MUST show positive slack on all paths).
- **Throughput**: ≥ 100 Mbps on the reconciled-key input stream.
- **Latency**: < 10 ms per block for blocks up to 10⁶ bits.
- **Logic utilization**: ≤ 80 % of total Logic Elements (LEs).
- **On-chip memory**: ≤ 80 % of available M9K / M144K blocks.

Timing failures MUST be resolved by architectural means (pipelining, retiming,
resource sharing) — relaxing clock constraints is FORBIDDEN.

### IV. Modular Architecture — Independently Testable Units

Each functional block MUST be a self-contained Verilog module with a defined
interface:

- **Input Buffer** — stores reconciled key blocks from Information Reconciliation.
- **Seed Generator / Loader** — generates or loads the N+L−1 seed bits for the
  hash matrix.
- **Hash Engine** — computes the Toeplitz matrix–vector product (N bits → L bits).
- **Compression Unit** — orchestrates Hash Engine and produces the final secret key.
- **Control Unit (FSM)** — state machine that sequences IDLE → LOAD → PROCESS
  → DONE → (optional) ERROR states.
- **Output Interface** — presents the L-bit secret key to downstream consumers.

Each module MUST have a dedicated testbench (`*_tb.v`) that can be simulated
independently in ModelSim/Questa Altera without requiring the full top-level.
Modules MUST expose `rst_n` (active-low synchronous reset) and a handshake
pair (`valid_in`/`ready_in`, `valid_out`/`ready_out`) or equivalent `start`/
`done` signals documented in the module header.

### V. Parametric Design — No Magic Numbers in RTL

Key sizing constants MUST be Verilog parameters, not literal integers:

- `N` — number of input (reconciled key) bits per block.
- `L` — number of output (secret key) bits per block.
- `W` — word width (parallelism granularity, default 8).
- `P` — output parallelism width (default 8); matrix_window = W+P−1.
- `DEPTH` — memory depth for input ROM / output RAM.

Parameters MUST be declared at the top of each module with inline comments
stating legal ranges and default values. Instantiation of a module with
out-of-range parameters MUST trigger a `$error` (simulation) or be caught by
a generate-time `if` guard.

Parametric changes MUST propagate atomically: RTL parameters, Python reference
model constants, and `.mif`/`.hex` test vectors MUST all be updated together
in the same commit.

## Hardware Platform Constraints

The implementation is locked to the following platform for the lifetime of
this project:

| Property | Value |
|---|---|
| Board | Altera DE2-115 |
| FPGA Device | Cyclone IV EP4CE115F29C7 |
| EDA Tool | Quartus Prime Lite (any compatible version) |
| Simulation | ModelSim-Altera / Questa Altera |
| IP Library | `altera_mf_ver` (simulation), `altera_mf` (synthesis) |
| Clock Source | 50 MHz on-board oscillator → ALTPLL for 100 MHz+ |
| Reset | KEY[0] (active-low push-button, debouncing optional for lab use) |
| Done Indicator | LEDR[0] |
| Verification Export | In-System Memory Content Editor (ORAM instance) |

**Prohibited practices**:
- Asynchronous resets (use synchronous active-low `rst_n` throughout).
- Combinatorial loops.
- Unregistered outputs on timing-critical paths.
- Synthesis attributes that disable timing analysis (e.g., `keep` on critical nets).
- Storing intermediate secret-key material in unprotected registers visible
  to external debug interfaces beyond what is required for lab validation
  (RNF-08 compliance).

**Quartus project files** (`*.qpf`, `*.qsf`) MUST be committed to version
control and MUST remain consistent with the HDL source set. The `.qsf` MUST
define:
- `TOP_LEVEL_ENTITY` pointing to the synthesizable top.
- `SEARCH_PATH` including `tb_mem_validation/` so `.mif` files are found.
- Device family and device part number.

## Development & Verification Workflow

All feature work MUST follow this four-step gate sequence:

1. **Reference Model First**
   Run `python3 high_level_simulation/gen_mif.py` to generate
   `input_vectors.mif` and `expected_outputs.hex` for the target parameter
   set. The Python model is the ground truth; RTL MUST match it.

2. **RTL Simulation (ModelSim)**
   From `src/tb_mem_validation/`:
   ```
   vlib work
   vlog *.v ../compression_unit.v ../hash_engine.v
   vsim -L altera_mf_ver work.top_mem_tb -do "run -all; quit"
   python3 ../../high_level_simulation/validate_dump.py
   ```
   Required result: `PASS: N/N vectors ok`. A partial pass or any FAIL
   is a blocking defect; the branch MUST NOT be merged.

3. **Synthesis & Timing**
   Open `src/lab_iv_privacy_amplification.qpf` in Quartus Prime Lite and
   run full compilation. Check:
   - Zero synthesis errors.
   - TimeQuest Fmax ≥ 100 MHz (all corners).
   - Resource summary ≤ 80 % LEs, ≤ 80 % memory blocks.

4. **FPGA Hardware Validation (DE2-115)**
   Program the `.sof`, cycle `KEY[0]`, confirm `LEDR[0]` asserts (done),
   read ORAM via In-System Memory Content Editor, and re-run
   `validate_dump.py` on the extracted hex. Result MUST be `PASS`.

No pull request to `main` is accepted without evidence (log or screenshot)
of passing gates 2, 3, and 4.

**Branch naming**: `test/<short-description>` for validation branches,
`feat/<short-description>` for new functionality.

## Governance

- This constitution supersedes all verbal agreements and informal conventions.
- Amendments require: (a) a written rationale in the PR description,
  (b) version bump per the semantic versioning policy below, and (c) update
  of this document and any affected templates in the same commit.
- **Versioning policy**:
  - MAJOR: Removal or redefinition of a principle; change to hash algorithm
    family; change to target platform.
  - MINOR: New principle, new constraint section, or material expansion of
    existing guidance.
  - PATCH: Clarifications, wording, typo fixes, non-semantic refinements.
- All code reviews MUST verify compliance with Principle I (synthesizability)
  and Principle II (reference-model parity) before approval.
- Complexity beyond what is minimally needed MUST be justified in the PR with
  a reference to a specific requirement ID (RF-xx, RNF-xx, or RD-xx).
- Runtime development guidance: see `RUN.md` at the repository root for
  step-by-step simulation and FPGA validation instructions.

**Version**: 1.0.0 | **Ratified**: 2026-05-23 | **Last Amended**: 2026-05-23
