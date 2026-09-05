#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
policy="${BEADSHX_IDENTITY_POLICY:-$repository_root/release/identity-policy.json}"

case "$policy" in
	/*) ;;
	*) policy="$repository_root/$policy" ;;
esac

cd "$repository_root"
jq -e '
	.schemaVersion == 1 and
	.product.name == "BeadsHX" and
	.product.developmentVersion == "0.0.0-development" and
	.product.releaseVersionFormat == "SemVer 2.0.0" and
	.product.firstPublicMajor == 1 and
	.binaries.development == "bdhx" and
	.binaries.upstreamOracle == "bd-upstream" and
	.binaries.developmentIdentity == "BeadsHX 0.0.0-development (compatible with Beads v1.2.1 at 634cbbc4bc580fa5124f63fdf65d137a46d5b4ff)" and
	(.binaries.forbiddenDevelopmentNames == ["bd", "beads"]) and
	.compatibilityTarget.version == "v1.2.1" and
	.compatibilityTarget.commit == "634cbbc4bc580fa5124f63fdf65d137a46d5b4ff" and
	.goModules.earlyInheritedModule == "github.com/steveyegge/beads" and
	.goModules.generatedPackage == "generated/go/bdhx" and
	.goModules.publicLibraryCandidate == "github.com/fullofcaffeine/beadshx" and
	.goModules.finalDecisionRequiredBefore == "BHX-M21-06" and
	.goModules.migrationPolicy.isolatedChange == true and
	.goModules.migrationPolicy.behaviorChangesAllowed == false and
	.goModules.migrationPolicy.atomicImportMigration == true and
	.buildMetadata.upstreamCompatibilityCommitRequired == true and
	.buildMetadata.requiredReleaseFields == ["productVersion", "beadshxCommit", "upstreamCompatibilityVersion", "upstreamCompatibilityCommit", "haxeGoCommit", "haxeVersion", "goVersion", "dirty"] and
	.userAgent.status == "reserved-not-emitted" and
	.userAgent.productPrefix == "BeadsHX/" and
	.userAgent.compatibilityToken == "compat/Beads-v1.2.1+634cbbc4bc58" and
	.userAgent.forbiddenPrefixes == ["bd/", "Beads/", "beads/"] and
	.bdAlias.status == "forbidden-before-post-soak-task" and
	.bdAlias.authorizingTask == "BHX-M21-07" and
	.bdAlias.requiredCompletedTasks == ["BHX-M21-03", "BHX-M21-04", "BHX-M21-05", "BHX-M21-06"] and
	.bdAlias.requirements.explicitInstallOption == true and
	.bdAlias.requirements.reversible == true and
	.bdAlias.requirements.reportsBeadsHXIdentity == true and
	.bdAlias.requirements.preservesDirectUpstreamFallback == "bd-upstream"
' "$policy" >/dev/null || {
	printf 'release identity policy does not match the admitted bootstrap contract: %s\n' "$policy" >&2
	exit 1
}

jq -e --slurpfile policy "$policy" '
	.compatibilityTarget.version == $policy[0].compatibilityTarget.version and
	.compatibilityTarget.commit == $policy[0].compatibilityTarget.commit
' engdocs/beadshx/program/source-locks.json >/dev/null

[[ "$(sed -n 's/^module //p' go.mod)" == "$(jq -r '.goModules.earlyInheritedModule' "$policy")" ]]
grep -Fqx -- '-D go_module=github.com/steveyegge/beads' compile.bootstrap.hxml
grep -Fqx -- "-D go_output=$(jq -r '.goModules.generatedPackage' "$policy")" compile.bootstrap.hxml
grep -Fqx -- '-D reflaxe_go_project=compile.bdhx.json' compile.bootstrap.hxml
jq -e --arg version "$(jq -r '.product.developmentVersion' "$policy")" '.version == $version' package.json >/dev/null
rg -Fq --glob '*.hx' \
	"$(jq -r '.binaries.developmentIdentity' "$policy")" src/beadshx
grep -Fq '"$repository_root/build/bin/bdhx"' scripts/beadshx/clean-generated.sh
grep -Fq 'output="$repository_root/build/bin/bd-upstream"' scripts/beadshx/build-upstream-oracle.sh

if rg -n -i 'user-agent|useragent' src/beadshx native/go >/dev/null; then
	printf 'bootstrap source emits a user agent before that identity surface is implemented\n' >&2
	exit 1
fi

printf 'release identity policy: PASS\n'
