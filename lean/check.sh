#!/usr/bin/env bash
# Container entry point for the Lean mechanization.
#   full   build every module, then check the axioms of the public results
#   smoke  build the process semantics only
#   shell  open a shell in the project
# Logs and summary.md are written to /results.
set -uo pipefail

MODE=${1:-full}
OUT=/results
PROJECT=/artifact/pact-formalization
ALLOWED="propext Classical.choice Quot.sound"

mkdir -p "$OUT"
cd "$PROJECT"

finish() {
    chown -R "$(stat -c %u:%g "$OUT")" "$OUT" 2>/dev/null
    exit "$1"
}

case "$MODE" in
shell)
    exec bash
    ;;
smoke)
    echo "== lake build Anvilpp.PactSemantics"
    lake build Anvilpp.PactSemantics 2>&1 | tee "$OUT/smoke_build.log"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ]; then echo "Smoke test passed: the process semantics build."; else echo "Smoke test FAILED (see smoke_build.log)."; fi
    finish "$rc"
    ;;
full)
    ;;
*)
    echo "usage: check.sh [full|smoke|shell]" >&2
    exit 2
    ;;
esac

echo "== lake build"
start=$(date +%s)
lake build 2>&1 | tee "$OUT/build.log"
build_rc=${PIPESTATUS[0]}
build_s=$(( $(date +%s) - start ))

echo "== lake env lean ProofAudit.lean"
lake env lean ProofAudit.lean 2>&1 | tee "$OUT/axioms.txt"
audit_rc=${PIPESTATUS[0]}

sorries=$(grep -c "declaration uses 'sorry'" "$OUT/build.log")
results=$(grep -cE "depends on axioms|does not depend on any axioms" "$OUT/axioms.txt")
bad=""
while IFS= read -r line; do
    name=$(sed -E "s/^'([^']*)'.*/\1/" <<<"$line")
    for ax in $(sed -E 's/.*\[(.*)\].*/\1/' <<<"$line" | tr ',' ' '); do
        case " $ALLOWED " in *" $ax "*) ;; *) bad+="$name: $ax"$'\n' ;; esac
    done
done < <(grep "depends on axioms" "$OUT/axioms.txt")

ok=1
[ "$build_rc" -eq 0 ] && [ "$audit_rc" -eq 0 ] && [ "$sorries" -eq 0 ] && [ -z "$bad" ] && [ "$results" -gt 0 ] || ok=0

{
    echo "# Lean mechanization"
    echo
    echo "| Check | Result |"
    echo "| --- | --- |"
    echo "| \`lake build\` | $([ "$build_rc" -eq 0 ] && echo "succeeded in ${build_s} s" || echo "FAILED (exit $build_rc)") |"
    echo "| Declarations using \`sorry\` | $sorries |"
    echo "| Public results audited (\`ProofAudit.lean\`) | $results |"
    echo "| Axioms outside $ALLOWED | $([ -z "$bad" ] && echo none || echo "$bad" | sed '/^$/d' | paste -sd ';' -) |"
    echo
    echo "Overall: $([ "$ok" -eq 1 ] && echo PASS || echo FAIL)"
} > "$OUT/summary.md"

echo
cat "$OUT/summary.md"
finish $(( 1 - ok ))
