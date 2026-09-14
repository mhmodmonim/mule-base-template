#!/usr/bin/env bash
# =============================================================================
#  Print a Markdown table of MUnit results from the surefire XML reports.
# =============================================================================
#  Usage: munit-summary.sh [report-dir]   (default target/surefire-reports)
#
#  Used for the GitHub Actions job summary. Azure DevOps reads the same XML
#  natively through PublishTestResults@2.
# =============================================================================
set -euo pipefail

dir="${1:-target/surefire-reports}"
shopt -s nullglob
reports=("$dir"/TEST-*.xml)

echo "## MUnit results"
echo
if ((${#reports[@]} == 0)); then
	echo "No MUnit reports found in \`${dir}\` - the build failed before tests ran, or tests were skipped."
	exit 0
fi

attr() {
	# $1 = attribute name, $2 = <testsuite ...> start tag
	sed -n "s/.* $1=\"\([^\"]*\)\".*/\1/p" <<<"$2"
}

echo "| Suite | Tests | Failures | Errors | Skipped | Time (s) |"
echo "| --- | ---: | ---: | ---: | ---: | ---: |"

total=0 failures=0 errors=0 skipped=0
for report in "${reports[@]}"; do
	tag="$(grep -o -m1 '<testsuite [^>]*>' "$report" || true)"
	[[ -n "$tag" ]] || continue
	t="$(attr tests "$tag")"; f="$(attr failures "$tag")"
	e="$(attr errors "$tag")"; s="$(attr skipped "$tag")"
	name="$(attr name "$tag")"
	total=$((total + ${t:-0})); failures=$((failures + ${f:-0}))
	errors=$((errors + ${e:-0})); skipped=$((skipped + ${s:-0}))
	icon="✅"; ((${f:-0} + ${e:-0} > 0)) && icon="❌"
	echo "| ${icon} ${name#MULE_EE.*.*.*.} | ${t:-0} | ${f:-0} | ${e:-0} | ${s:-0} | $(attr time "$tag") |"
done

echo "| **Total** | **${total}** | **${failures}** | **${errors}** | **${skipped}** | |"
echo
echo "Coverage report: download the \`munit-reports\` artifact and open \`coverage/summary.html\`."
