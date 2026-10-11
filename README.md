# Pact: artifact for *A Type System for Communication Safe Hardware Design* (POPL 2027)

This artifact contains two parts, included as git submodules:

| Part | Submodule | Contents |
| --- | --- | --- |
| Benchmarks | [`pact-experiments`](https://github.com/AnvilHDL/Pact-Experiments) | The ten hardware benchmarks, written in Pact and as SystemVerilog references. Includes the scripts for compatibility checking, model checking, synthesis and trace equivalence. Its container builds the [Pact compiler](https://github.com/AnvilHDL/pact) at a pinned commit. |
| Mechanization | [`pact-formalization`](https://github.com/AnvilHDL/Pact-formalization) | Lean 4 definitions and proofs for Pact processes, types, compatibility and inferred-type optimality. |

`evaluate.sh` builds a container image for each part and runs every experiment from a menu or a single command. It uses Podman when available, and Docker otherwise.

## Requirements

| | |
| --- | --- |
| Machine | Linux on x86-64, 8 or more cores |
| Memory | 16 GB |
| Disk | 30 GB for both images |
| Software | Podman or Docker, git, bash |
| Network | Needed to build the images, unless they are loaded from `images/*.tar` |

## Getting started

```sh
git clone --recurse-submodules <this repository> pact-artifact
cd pact-artifact
./evaluate.sh            # menu
```

Or run the same steps as commands:

```sh
./evaluate.sh check      # prerequisites, submodules, images
./evaluate.sh build      # build both images
./evaluate.sh smoke      # kick the tires
./evaluate.sh summary    # print the results
```

Building the images downloads the tool chains: OCaml, Yosys, SymbiYosys, Verilator, the sky130 PDK, OpenSTA, Lean and Mathlib's prebuilt files.

The smoke test runs four benchmark experiments on a few cases:

- the AXI communication-error cases;
- compatibility checking of FIFO, arbiter and TileLink (one repetition);
- synthesis of FIFO and arbiter;
- trace equivalence of the four common cells.

It then builds the process semantics of the Lean development.

Every benchmark result is printed as `expected / measured`, and the Lean result as a pass/fail table. Results are written to `results/` on the host.

## Claims and how to check them

### Benchmarks (`pact-experiments`)

| Paper claim | Command | Result |
| --- | --- | --- |
| Table *Compatibility-checking time and circuit synthesis results*, compatibility checking: every pool is compatible, with Pact's checking times | `./evaluate.sh bench compat` | `results/benchmarks/timing_<time>/comparison.md` |
| Same table, SV model checking columns | `./evaluate.sh bench modelcheck` | `results/benchmarks/timing_<time>/comparison.md` |
| Same table, synthesis results: area, and meeting timing at 100 MHz | `./evaluate.sh bench synthesis` | `results/benchmarks/synthesis_<time>/comparison.md` |
| Same table, cycle latency overhead 0: each Pact design matches its SV reference cycle for cycle | `./evaluate.sh bench equiv` | `results/benchmarks/equiv/`; an empty `logic.diff` means a match |
| Appendix table *Completed AXI communication-error case studies*, and the incremental AXI demux check in *Utility on Real-World Communication Errors* | `./evaluate.sh bench opencompat` | `results/benchmarks/opencompat_<time>/comparison.md` |

Verdicts, areas and flip-flop counts are deterministic. Times depend on the machine; the expected times were measured on 2× AMD EPYC 9115 with 125 GB of memory.

On that machine:

| Run | Time |
| --- | --- |
| `bench compat` | about 1.5 h |
| `bench modelcheck` | about 9 h with `SV_JOBS=4`. Some runs reach their 2 h limit by design; set `SV_JOBS` to the number of parallel runs the machine can hold, at about 4 GB each. |
| `bench synthesis` | about 10 min |
| `bench equiv` | a few minutes per benchmark |

The [benchmark README](pact-experiments/README.md) gives the expected values and how each experiment is run.

### Mechanization (`pact-formalization`)

```sh
./evaluate.sh lean
```

This command:

- builds every module with the pinned Lean toolchain;
- reports any declaration that uses `sorry`;
- runs `ProofAudit.lean`, which prints the axioms of each public result;
- checks that those axioms are only `propext`, `Classical.choice` and `Quot.sound`.

The summary is in `results/lean/summary.md`.

| Paper result | Lean declaration (namespace `Pact`, [`Anvilpp/PactSafety.lean`](pact-formalization/Anvilpp/PactSafety.lean)) |
| --- | --- |
| Lemma *Strategy transfer* | `strategy_transfer` |
| Lemma *Soundness of inferred types* | `inferred_type_soundness` |
| Lemma *Conformance is closed under refinement* | `conformance_closed_under_refinement` |
| Lemma *Soundness of type checking* | `type_checking_soundness`, `compositional_type_checking_soundness` |
| Lemma *Type–automaton correspondence* | `type_automaton_correspondence` |
| Lemma *Process–automaton correspondence* | `process_automaton_correspondence`, `process_automaton_path` |
| Theorem *Correctness of the game reduction* | `game_reduction_correctness`, `log_objective_regular` |
| Theorem *Soundness of type compatibility* | `type_compatibility_soundness` |
| Lemma *Compatibility is monotone under type refinement* | `compatibility_monotone_under_refinement` |
| Theorem *Optimality of inferred types* | `inferred_types_optimal` |
| Corollary *Failure rules out data-oblivious proofs* | `inferred_failure_rules_out_data_oblivious_proofs` |

[RESULTS.md](pact-formalization/RESULTS.md) states each result with its premises and proof chain.

### Not covered

- The theorems on decidability and complexity of type inference, type checking and compatibility are not mechanized.
- Wall-clock times are not expected to match on a different machine. The relative comparison between Pact and SymbiYosys, and the verdicts, are.

## Updates since submission

The results in this artifact are revised from the submitted paper.

- [`pact-experiments/README.md`](pact-experiments/README.md) lists the current benchmark results.
- [`pact-experiments/OPTIMIZATIONS.md`](pact-experiments/OPTIMIZATIONS.md) describes the compiler optimizations behind them.
- [`pact-formalization/Update.md`](pact-formalization/Update.md) summarizes how the mechanization makes the paper's definitions and theorem statements precise.

## Other commands

| Command | Purpose |
| --- | --- |
| `./evaluate.sh shell bench` | Shell in the benchmark container. The repository is in `/artifact/Pact-Experiments` and the compiler in `/artifact/Pact`. |
| `./evaluate.sh shell lean` | Shell in the Lean container, in `/artifact/pact-formalization` |
| `./evaluate.sh bench check` | Session type check of every benchmark process against its interfaces |
| `./evaluate.sh bench all` | Every benchmark experiment |
| `./evaluate.sh save` | Save both images to `images/*.tar`; `build` loads them from there if present |

`ENGINE=docker` selects Docker when both engines are installed. `RESULTS=<dir>` changes the results directory.
