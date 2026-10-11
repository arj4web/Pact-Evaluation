#!/usr/bin/env bash
# Push-button evaluation of the Pact artifact.
# Run without arguments for a menu, or with a command (see `./evaluate.sh help`).
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESULTS=${RESULTS:-$ROOT/results}
IMAGES=$ROOT/images
BENCH_IMAGE=${BENCH_IMAGE:-pact-experiments}
LEAN_IMAGE=${LEAN_IMAGE:-pact-lean}
SV_JOBS=${SV_JOBS:-4}

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Podman if available, otherwise Docker; ENGINE=docker overrides.
if [ -z "${ENGINE:-}" ]; then
    if command -v podman >/dev/null 2>&1; then ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then ENGINE=docker
    else ENGINE=""
    fi
fi

need_engine() { [ -n "$ENGINE" ] || die "Neither podman nor docker was found. Install one of them first."; }
have_image() { $ENGINE image inspect "$1" >/dev/null 2>&1; }

need_submodules() {
    if [ ! -f "$ROOT/pact-experiments/Dockerfile" ] || [ ! -f "$ROOT/pact-formalization/lakefile.toml" ] \
       || [ -z "$(ls -A "$ROOT/pact-experiments/axi" 2>/dev/null)" ]; then
        say "Fetching submodules"
        git -C "$ROOT" submodule update --init --recursive || die "Could not fetch the submodules."
    fi
}

# ---------------------------------------------------------------- setup

cmd_check() {
    say "Prerequisites"
    printf '  container engine : %s\n' "${ENGINE:-none found}"
    [ -n "$ENGINE" ] && printf '  engine version   : %s\n' "$($ENGINE --version 2>/dev/null | head -1)"
    printf '  CPU cores        : %s (8 or more recommended)\n' "$(nproc 2>/dev/null || echo ?)"
    if [ -r /proc/meminfo ]; then
        printf '  memory           : %s GB (16 GB or more recommended)\n' "$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)"
    fi
    printf '  free disk        : %s (30 GB needed for both images)\n' "$(df -h "$ROOT" | awk 'NR==2 {print $4}')"
    for d in pact-experiments pact-formalization; do
        if [ -n "$(ls -A "$ROOT/$d" 2>/dev/null)" ]; then
            printf '  %-17s: %s\n' "$d" "$(git -C "$ROOT/$d" rev-parse --short HEAD 2>/dev/null || echo present)"
        else
            printf '  %-17s: missing (run ./evaluate.sh build, or git submodule update --init --recursive)\n' "$d"
        fi
    done
    if [ -n "$ENGINE" ]; then
        printf '  %-17s: %s\n' "$BENCH_IMAGE image" "$(have_image "$BENCH_IMAGE" && echo built || echo 'not built')"
        printf '  %-17s: %s\n' "$LEAN_IMAGE image" "$(have_image "$LEAN_IMAGE" && echo built || echo 'not built')"
    fi
}

build_one() {
    local name=$1 image=$2
    shift 2
    if have_image "$image"; then
        say "Image $image is already built"
    elif [ -f "$IMAGES/$image.tar" ]; then
        say "Loading $image from images/$image.tar"
        $ENGINE load -i "$IMAGES/$image.tar" || die "Could not load images/$image.tar."
    else
        say "Building the $name image ($image)"
        $ENGINE build -t "$image" "$@" || die "Building $image failed."
    fi
}

cmd_build() {
    need_engine
    need_submodules
    local what=${1:-all}
    case "$what" in bench|lean|all) ;; *) die "build: expected bench, lean or all" ;; esac
    if [ "$what" != lean ]; then build_one benchmarks "$BENCH_IMAGE" "$ROOT/pact-experiments"; fi
    if [ "$what" != bench ]; then build_one Lean "$LEAN_IMAGE" -f "$ROOT/lean/Dockerfile" "$ROOT"; fi
}

cmd_save() {
    need_engine
    mkdir -p "$IMAGES"
    for image in "$BENCH_IMAGE" "$LEAN_IMAGE"; do
        have_image "$image" || die "Image $image is not built."
        say "Saving $image to images/$image.tar"
        $ENGINE save -o "$IMAGES/$image.tar" "$image" || die "Could not save $image."
    done
}

# ---------------------------------------------------------------- runs

run_bench() {
    need_engine
    have_image "$BENCH_IMAGE" || cmd_build bench
    mkdir -p "$RESULTS/benchmarks"
    $ENGINE run --rm -v "$RESULTS/benchmarks:/artifact/Pact-Experiments/results:z" "$BENCH_IMAGE" "$@"
}

run_lean() {
    need_engine
    have_image "$LEAN_IMAGE" || cmd_build lean
    mkdir -p "$RESULTS/lean"
    $ENGINE run --rm -v "$RESULTS/lean:/results:z" "$LEAN_IMAGE" "$@"
}

BENCH_SMOKE='make opencompat \
 && python3 scripts/run_timing.py --part pact --case fifo --case arbiter --case tilelink --reps 1 --results-dir results/smoke/timing \
 && python3 scripts/run_synthesis.py --case fifo --case arbiter --results-dir results/smoke/synthesis \
 && bash scripts/run_common_cells_cycle_equiv.sh'

cmd_smoke() {
    say "Kick the tires: benchmarks"
    run_bench bash -c "$BENCH_SMOKE" || die "Benchmark smoke test failed."
    say "Kick the tires: Lean"
    run_lean smoke || die "Lean smoke test failed."
    say "Smoke test passed. Results are in $RESULTS."
}

cmd_bench() {
    local target=${1:-}
    case "$target" in
        opencompat|synthesis|equiv|compat|check)
            say "Benchmarks: make $target"
            run_bench make "$target" ;;
        modelcheck)
            say "Benchmarks: make modelcheck SV_JOBS=$SV_JOBS"
            run_bench make modelcheck SV_JOBS="$SV_JOBS" ;;
        all)
            say "Benchmarks: make all SV_JOBS=$SV_JOBS"
            run_bench make all SV_JOBS="$SV_JOBS" ;;
        *) die "bench: expected opencompat, synthesis, equiv, compat, modelcheck, check or all" ;;
    esac
}

cmd_lean() {
    say "Lean mechanization: build and axiom audit"
    run_lean full
}

cmd_summary() {
    say "Results in $RESULTS"
    local found=0 f
    while IFS= read -r f; do
        found=1
        printf '\n== %s\n' "${f#"$RESULTS"/}"
        cat "$f"
    done < <(find "$RESULTS" -name comparison.md -o -name summary.md 2>/dev/null | sort)
    if [ -d "$RESULTS/benchmarks/equiv" ]; then
        printf '\n== trace equivalence (an empty logic.diff means the traces match)\n'
        find "$RESULTS/benchmarks/equiv" -name logic.diff | sort | while read -r f; do
            printf '  %-70s %s\n' "${f#"$RESULTS"/}" "$([ -s "$f" ] && echo DIFFERS || echo match)"
        done
    fi
    [ "$found" -eq 1 ] || warn "No results yet."
}

cmd_shell() {
    case "${1:-bench}" in
        bench) need_engine; mkdir -p "$RESULTS/benchmarks"
               $ENGINE run --rm -it -v "$RESULTS/benchmarks:/artifact/Pact-Experiments/results:z" "$BENCH_IMAGE" bash ;;
        lean)  need_engine; mkdir -p "$RESULTS/lean"
               $ENGINE run --rm -it -v "$RESULTS/lean:/results:z" "$LEAN_IMAGE" shell ;;
        *) die "shell: expected bench or lean" ;;
    esac
}

usage() {
    cat <<EOF
Usage: ./evaluate.sh [command]

  check                 Show prerequisites and what is built
  build [bench|lean|all]
                        Build the container images (or load them from images/*.tar)
  smoke                 Kick the tires: small benchmark runs and a partial Lean build
  lean                  Build the Lean proofs and audit their axioms
  bench <experiment>    Run one benchmark experiment:
                          opencompat  AXI communication-error cases (seconds)
                          synthesis   area and timing (about 10 min)
                          equiv       cycle-level trace equivalence (minutes)
                          compat      compatibility-checking time (about 1.5 h)
                          modelcheck  SymbiYosys model checking (hours; SV_JOBS=$SV_JOBS in parallel)
                          all         all of the above
  summary               Print every result summary
  shell [bench|lean]    Open a shell in a container
  save                  Save both images to images/*.tar

Environment: ENGINE (podman or docker), SV_JOBS, RESULTS (default ./results).
Without a command, a menu is shown.
EOF
}

menu() {
    while true; do
        cat <<EOF

Pact artifact evaluation  (engine: ${ENGINE:-none}, results: $RESULTS)

  Setup
    1) Check prerequisites
    2) Build both container images
  Kick the tires
    3) Smoke test (benchmarks and Lean)
  Lean mechanization
    4) Build the proofs and audit their axioms
  Benchmarks
    5) AXI communication-error cases   (seconds)
    6) Area and timing                 (about 10 min)
    7) Trace equivalence               (minutes)
    8) Compatibility-checking time     (about 1.5 h)
    9) SymbiYosys model checking       (hours)
  Results
   10) Print result summaries
    q) Quit
EOF
        read -r -p "Choice: " choice || exit 0
        case "$choice" in
            1) cmd_check ;;
            2) cmd_build all ;;
            3) cmd_smoke ;;
            4) cmd_lean ;;
            5) cmd_bench opencompat ;;
            6) cmd_bench synthesis ;;
            7) cmd_bench equiv ;;
            8) cmd_bench compat ;;
            9) read -r -p "Parallel SymbiYosys runs [$SV_JOBS]: " j; SV_JOBS=${j:-$SV_JOBS}; cmd_bench modelcheck ;;
            10) cmd_summary ;;
            q|Q) exit 0 ;;
            *) warn "Unknown choice: $choice" ;;
        esac
    done
}

case "${1:-}" in
    "") menu ;;
    check) cmd_check ;;
    build) shift; cmd_build "$@" ;;
    smoke) cmd_smoke ;;
    lean) cmd_lean ;;
    bench) shift; cmd_bench "$@" ;;
    summary) cmd_summary ;;
    shell) shift; cmd_shell "$@" ;;
    save) cmd_save ;;
    help|-h|--help) usage ;;
    *) usage; exit 2 ;;
esac
