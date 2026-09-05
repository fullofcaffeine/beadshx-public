#!/usr/bin/env bash
set -uo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
command_name="${1:-}"
log_root="$repository_root/build/evidence/commands"
go_toolchain="$(jq -er '.common.go' \
	"$repository_root/engdocs/beadshx/program/toolchain-locks.json")"
export GOWORK=off
export GOTOOLCHAIN="$go_toolchain"

usage() {
	printf 'usage: %s {setup|bootstrap|generate|build|oracle|inventory|inventory-check|output-contracts|error-contracts|storage-contracts|effect-contracts|daily-workflow|native-pressure|schema-migrations|test-focused|generated|identity|caf-intent|parity|test|ci-local|format|lint|package|clean}\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
	usage
	exit 2
fi

run_command() {
	case "$command_name" in
	setup) "$repository_root/scripts/beadshx/setup-haxe.sh" ;;
	bootstrap) "$repository_root/scripts/beadshx/check-bootstrap.sh" ;;
	generate) "$repository_root/scripts/beadshx/generate-source.sh" ;;
	build) "$repository_root/scripts/beadshx/build-generated.sh" ;;
	oracle) "$repository_root/scripts/beadshx/build-upstream-oracle.sh" ;;
	inventory)
		(
			cd "$repository_root"
			go run ./scripts/beadshx/command-inventory --repository "$repository_root"
		)
		;;
	inventory-check) "$repository_root/scripts/beadshx/test-command-inventory.sh" ;;
	output-contracts) "$repository_root/scripts/beadshx/test-output-contracts.sh" ;;
	error-contracts) "$repository_root/scripts/beadshx/test-error-contracts.sh" ;;
	storage-contracts) "$repository_root/scripts/beadshx/test-storage-contracts.sh" ;;
	effect-contracts) "$repository_root/scripts/beadshx/test-effect-contracts.sh" ;;
	daily-workflow) "$repository_root/scripts/beadshx/test-daily-workflow.sh" ;;
	native-pressure) "$repository_root/scripts/beadshx/test-native-pressure.sh" ;;
	schema-migrations) "$repository_root/scripts/beadshx/schema-migration-graph.sh" check ;;
	test-focused)
		"$repository_root/scripts/beadshx/test-data-safety.sh" &&
			"$repository_root/scripts/beadshx/test-toolchain-locks.sh" &&
			"$repository_root/scripts/beadshx/test-bdhx-entrypoint.sh" &&
			(cd "$repository_root" && "$repository_root/node_modules/.bin/haxe" test/query/compile.hxml) &&
			(cd "$repository_root" && "$repository_root/node_modules/.bin/haxe" test/ready/compile.hxml) &&
			(cd "$repository_root" && "$repository_root/node_modules/.bin/haxe" test/relation/compile.hxml) &&
			"$repository_root/scripts/beadshx/test-storage-transaction-tracer.sh" &&
			(cd "$repository_root" && go test -tags gms_pure_go \
				./internal/beadshx/... ./generated/go/bdhx)
		;;
	generated) "$repository_root/scripts/beadshx/test-generated-governance.sh" ;;
	identity) "$repository_root/scripts/beadshx/test-release-identity.sh" ;;
	caf-intent) "$repository_root/scripts/beadshx/test-caf-provider-intent.sh" ;;
	parity)
		{ [[ -x "$repository_root/build/bin/bdhx" ]] || "$repository_root/scripts/beadshx/generate-bootstrap.sh"; } &&
			{ [[ -x "$repository_root/build/bin/bd-upstream" ]] || "$repository_root/scripts/beadshx/build-upstream-oracle.sh"; } &&
		"$repository_root/scripts/beadshx/test-parity-smoke.sh"
		;;
	test)
		"$repository_root/scripts/beadshx/check-bootstrap.sh" &&
			"$repository_root/scripts/beadshx/build-upstream-oracle.sh" &&
		"$repository_root/scripts/beadshx/test-parity-smoke.sh"
		;;
	ci-local) "$repository_root/scripts/beadshx/ci-local.sh" ;;
	format)
		goroot="$(go env GOROOT)" &&
		PATH="$repository_root/node_modules/.bin:$PATH" \
			"$repository_root/node_modules/.bin/lix" run formatter \
			-s "$repository_root/src/beadshx" &&
		while IFS= read -r -d '' go_file; do
			"$goroot/bin/gofmt" -w "$go_file"
		done < <(find "$repository_root/native/go" \
			-type f -name '*.go' -print0 2>/dev/null)
		;;
	lint)
		bash -n "$repository_root"/scripts/beadshx/*.sh &&
			"$repository_root/scripts/beadshx/check-haxe-format.sh" &&
			"$repository_root/scripts/beadshx/check-bootstrap.sh"
		;;
	package)
		"$repository_root/scripts/beadshx/package-bootstrap.sh"
		;;
	clean) "$repository_root/scripts/beadshx/clean-generated.sh" ;;
	*) usage; return 2 ;;
	esac
}

mkdir -p "$log_root"
log="$log_root/$command_name.log"
if run_command >"$log" 2>&1; then
	status=pass
	exit_code=0
else
	exit_code=$?
	status=fail
fi

jq -cn \
	--arg command "$command_name" \
	--arg status "$status" \
	--arg log "build/evidence/commands/$command_name.log" \
	--argjson exitCode "$exit_code" \
	'{schemaVersion:1, command:$command, status:$status, exitCode:$exitCode, log:$log}'
exit "$exit_code"
