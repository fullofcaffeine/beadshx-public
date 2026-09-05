# Go dependency and native-boundary pressure

This report is generated from Beads `634cbbc4bc580fa5124f63fdf65d137a46d5b4ff` with `golang.org/x/tools/go/packages+go/types`. It ranks pressure against haxe.go `c1e3333d2ce358b451e69b2b1530030bc4083dd5` without treating the Go dependency graph as the Haxe product model.

The complete machine-readable call inventory is `inventory.json.gz`. The report groups those calls by typed native boundary and dependency policy.

## Coverage

- 2 build profiles
- 93 reachable first-party packages
- 67 packages assigned to a native boundary
- 2920 deduplicated typed boundary calls
- 0 unmapped calls, effects, command profiles, or storage capabilities

## Ranked haxe.go feature pressure

| Priority | Feature | Observed pressure | Axes | Decision |
| --- | --- | ---: | --- | --- |
| P0 | `typed-records-and-results` | 1031 | `multipleReturns` | Convert boundary results immediately into named Haxe records, enums, or go.Result values; do not expose positional implementation detail to domain code. |
| P0 | `extern-first-native-boundaries` | 680 | `cgo`, `platformSpecific`, `pointer` | Port first-party Beads behavior to authored Haxe. Use precise externs for Go standard-library and independent third-party APIs underneath the port, and fix reusable haxe.go gaps before retaining only a proven third-party or platform native island. |
| P1 | `interface-method-sets` | 1683 | `interface` | Generate precise interface externs and route reusable method-set failures to haxe.go. Do not replace exported interfaces with product-specific Go wrappers. |
| P1 | `context-and-cancellation` | 695 | `context` | Haxe owns cancellation intent and deadlines and consumes context APIs through precise externs. Keep native construction only when an unexported or lifetime constraint is proven. |
| P1 | `callback-boundaries` | 46 | `callback` | Prove bounded callback signatures with precise externs and a reduced compiler fixture. Retain callback execution in a native island only while an exact safe binding remains unsupported. |
| P1 | `concrete-generic-adapters` | 46 | `generic` | Represent supported concrete generic instantiations through precise externs. Keep Haxe-owned policy and collections in authored Haxe and report unsupported shapes explicitly. |
| P1 | `go-owned-concurrency` | 12 | `channel` | Use typed channel and concurrency externs when haxe.go can preserve their semantics. Retain only proven host lifecycle and cleanup effects in a narrow native island. |

Counts are pressure signals. One call can contribute to more than one axis, so feature totals are not additive.

## Extern-first native boundaries

Haxe owns every first-party Beads implementation. It consumes Go standard-library and independent third-party APIs through precise externs. A handwritten native island is retained only for a third-party or platform boundary that a reduced compiler proof cannot represent safely.

| Priority | Boundary | Boundary calls | Main pressure | Role |
| --- | --- | ---: | --- | --- |
| P0 | `facade:command-host` | 1456 | `interface` 841, `multipleReturns` 514, `context` 425, `pointer` 325 | CLI orchestration and presentation edge |
| P0 | `facade:storage-runtime` | 542 | `interface` 275, `multipleReturns` 156, `pointer` 59, `platformSpecific` 57 | Beads storage source family over Dolt, SQL, migration, transaction, and database-service APIs |
| P0 | `facade:http-runtime` | 295 | `interface` 192, `multipleReturns` 139, `context` 71, `pointer` 25 | HTTP server, event stream, and work API lifecycle |
| P0 | `facade:platform-runtime` | 232 | `interface` 97, `platformSpecific` 51, `multipleReturns` 50, `pointer` 26 | Filesystem, Git, process, terminal, credential, lock, and platform mechanics |
| P0 | `facade:integration-runtime` | 191 | `interface` 92, `multipleReturns` 42, `context` 27, `pointer` 27 | Remote tracker, AI, mapping, and synchronization adapters |
| P1 | `facade:telemetry-runtime` | 204 | `interface` 186, `multipleReturns` 130, `context` 123, `pointer` 39 | OpenTelemetry storage decorators and exporters |

## Dependency ownership

| Priority | Package or module | Boundary calls | Policy | Owner | Main pressure |
| --- | --- | ---: | --- | --- | --- |
| P0 | `os` | 166 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 132, `multipleReturns` 72, `platformSpecific` 28 |
| P0 | `database/sql` | 63 | `storage-engine` | `haxe-extern-first-or-proven-native-island` | `interface` 49, `multipleReturns` 24, `context` 21 |
| P0 | `github.com/spf13/cobra` | 33 | `cli-presentation` | `haxe-domain` | `pointer` 11, `interface` 8, `callback` 1 |
| P0 | `net` | 33 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 21, `multipleReturns` 11, `context` 1 |
| P0 | `net/http` | 32 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 20, `pointer` 10, `multipleReturns` 7 |
| P0 | `github.com/spf13/viper` | 29 | `cli-presentation` | `haxe-domain` | `interface` 4, `pointer` 3 |
| P0 | `charm.land/huh/v2` | 27 | `cli-presentation` | `haxe-domain` | `pointer` 25, `generic` 6, `interface` 6 |
| P0 | `context` | 27 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 20, `context` 15, `multipleReturns` 6 |
| P0 | `charm.land/lipgloss/v2` | 17 | `cli-presentation` | `haxe-domain` | `interface` 5 |
| P0 | `net/url` | 16 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `multipleReturns` 6, `interface` 5, `pointer` 4 |
| P0 | `github.com/dolthub/dolt/go` | 12 | `storage-engine` | `haxe-extern-first-or-proven-native-island` | `interface` 3, `multipleReturns` 2, `pointer` 1 |
| P0 | `golang.org/x/sys` | 11 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 11, `platformSpecific` 11, `pointer` 4 |
| P0 | `runtime` | 10 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 3, `pointer` 2, `multipleReturns` 1 |
| P0 | `golang.org/x/sync` | 5 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 5, `callback` 2, `context` 1 |
| P0 | `golang.org/x/term` | 5 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `interface` 2, `multipleReturns` 2, `cgo` 1 |
| P0 | `github.com/go-sql-driver/mysql` | 4 | `storage-engine` | `haxe-extern-first-or-proven-native-island` | `interface` 2, `pointer` 2, `multipleReturns` 1 |
| P0 | `syscall` | 4 | `host-runtime` | `haxe-extern-first-or-proven-native-island` | `platformSpecific` 4, `interface` 3, `multipleReturns` 1 |
| P0 | `github.com/dolthub/driver/v2` | 3 | `storage-engine` | `haxe-extern-first-or-proven-native-island` | `cgo` 3, `interface` 3, `platformSpecific` 3 |
| P0 | `github.com/charmbracelet/x/ansi` | 1 | `cli-presentation` | `haxe-domain` | none |
| P1 | `go.opentelemetry.io/otel/trace` | 33 | `telemetry-sdk` | `haxe-extern-first` | `interface` 23, `context` 5, `multipleReturns` 5 |
| P1 | `go.opentelemetry.io/otel/metric` | 27 | `telemetry-sdk` | `haxe-extern-first` | `interface` 26, `multipleReturns` 8, `context` 7 |
| P1 | `go.opentelemetry.io/otel` | 25 | `telemetry-sdk` | `haxe-extern-first` | `interface` 8, `platformSpecific` 2 |
| P1 | `github.com/dolthub/eventkit` | 16 | `telemetry-sdk` | `haxe-extern-first` | `pointer` 8, `interface` 6, `context` 2 |
| P1 | `github.com/anthropics/anthropic-sdk-go` | 12 | `remote-sdk` | `haxe-extern-first` | `context` 2, `interface` 2, `multipleReturns` 2 |
| P1 | `go.opentelemetry.io/otel/sdk` | 10 | `telemetry-sdk` | `haxe-extern-first` | `interface` 10, `pointer` 3, `context` 1 |
| P1 | `go.opentelemetry.io/otel/sdk/metric` | 5 | `telemetry-sdk` | `haxe-extern-first` | `interface` 5, `pointer` 3 |
| P1 | `go.opentelemetry.io/otel/exporters/stdout/stdouttrace` | 2 | `telemetry-sdk` | `haxe-extern-first` | `interface` 2, `multipleReturns` 1, `pointer` 1 |
| P1 | `go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp` | 1 | `telemetry-sdk` | `haxe-extern-first` | `context` 1, `interface` 1, `multipleReturns` 1 |
| P1 | `go.opentelemetry.io/otel/exporters/stdout/stdoutmetric` | 1 | `telemetry-sdk` | `haxe-extern-first` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/steveyegge/beads` | 1469 | `pure-value` | `haxe-domain` | `interface` 1037, `multipleReturns` 723, `context` 630 |
| P2 | `strings` | 147 | `pure-value` | `haxe-domain` | `multipleReturns` 18, `platformSpecific` 16, `interface` 13 |
| P2 | `time` | 127 | `pure-value` | `haxe-domain` | `platformSpecific` 10, `interface` 8, `multipleReturns` 8 |
| P2 | `io` | 64 | `pure-value` | `haxe-domain` | `interface` 27, `multipleReturns` 21, `platformSpecific` 6 |
| P2 | `sync` | 57 | `pure-value` | `haxe-domain` | `callback` 6, `multipleReturns` 3, `pointer` 3 |
| P2 | `path` | 40 | `pure-value` | `haxe-domain` | `interface` 17, `multipleReturns` 14, `platformSpecific` 4 |
| P2 | `github.com/spf13/pflag` | 36 | `pure-value` | `haxe-domain` | `pointer` 21, `interface` 12, `multipleReturns` 8 |
| P2 | `bytes` | 32 | `pure-value` | `haxe-domain` | `interface` 7, `multipleReturns` 5, `pointer` 3 |
| P2 | `encoding/json` | 32 | `pure-value` | `haxe-domain` | `interface` 25, `multipleReturns` 8, `pointer` 6 |
| P2 | `fmt` | 32 | `pure-value` | `haxe-domain` | `interface` 25, `multipleReturns` 19, `platformSpecific` 8 |
| P2 | `regexp` | 29 | `pure-value` | `haxe-domain` | `pointer` 4, `callback` 1, `interface` 1 |
| P2 | `strconv` | 29 | `pure-value` | `haxe-domain` | `interface` 18, `multipleReturns` 18, `platformSpecific` 6 |
| P2 | `crypto` | 23 | `pure-value` | `haxe-domain` | `interface` 12, `multipleReturns` 8, `callback` 1 |
| P2 | `slices` | 20 | `pure-value` | `haxe-domain` | `generic` 20, `interface` 19, `callback` 5 |
| P2 | `errors` | 18 | `pure-value` | `haxe-domain` | `interface` 18, `platformSpecific` 4 |
| P2 | `bufio` | 16 | `pure-value` | `haxe-domain` | `interface` 8, `pointer` 5, `multipleReturns` 2 |
| P2 | `sort` | 15 | `pure-value` | `haxe-domain` | `callback` 7, `interface` 2, `platformSpecific` 1 |
| P2 | `reflect` | 11 | `pure-value` | `haxe-domain` | `interface` 1 |
| P2 | `gopkg.in/yaml.v3` | 9 | `pure-value` | `haxe-domain` | `interface` 8, `multipleReturns` 3, `pointer` 1 |
| P2 | `unicode` | 9 | `pure-value` | `haxe-domain` | `cgo` 2, `platformSpecific` 2, `multipleReturns` 1 |
| P2 | `math` | 8 | `pure-value` | `haxe-domain` | `interface` 2, `pointer` 1 |
| P2 | `text` | 8 | `pure-value` | `haxe-domain` | `interface` 6, `pointer` 5, `multipleReturns` 2 |
| P2 | `encoding/hex` | 5 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/cenkalti/backoff/v4` | 5 | `pure-value` | `haxe-domain` | `interface` 4, `context` 1, `pointer` 1 |
| P2 | `hash` | 5 | `pure-value` | `haxe-domain` | `interface` 1 |
| P2 | `log` | 5 | `pure-value` | `haxe-domain` | `interface` 2, `pointer` 2 |
| P2 | `encoding/csv` | 4 | `pure-value` | `haxe-domain` | `interface` 3, `pointer` 1 |
| P2 | `github.com/google/uuid` | 4 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/yuin/goldmark` | 4 | `pure-value` | `haxe-domain` | `interface` 4 |
| P2 | `testing` | 4 | `pure-value` | `haxe-domain` | `callback` 1 |
| P2 | `cmp` | 3 | `pure-value` | `haxe-domain` | `generic` 3, `interface` 3 |
| P2 | `encoding/base64` | 3 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/BurntSushi/toml` | 3 | `pure-value` | `haxe-domain` | `interface` 3, `multipleReturns` 1, `pointer` 1 |
| P2 | `encoding/binary` | 2 | `pure-value` | `haxe-domain` | none |
| P2 | `github.com/microcosm-cc/bluemonday` | 2 | `pure-value` | `haxe-domain` | `pointer` 1 |
| P2 | `github.com/subosito/gotenv` | 2 | `pure-value` | `haxe-domain` | `interface` 2, `multipleReturns` 1 |
| P2 | `embed` | 1 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/JohannesKaufmann/html-to-markdown/v2` | 1 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |
| P2 | `github.com/invopop/jsonschema` | 1 | `pure-value` | `haxe-domain` | `pointer` 1 |
| P2 | `golang.org/x/net` | 1 | `pure-value` | `haxe-domain` | `interface` 1 |
| P2 | `gopkg.in/src-d/go-errors.v1` | 1 | `pure-value` | `haxe-domain` | `interface` 1 |
| P2 | `html` | 1 | `pure-value` | `haxe-domain` | none |
| P2 | `maps` | 1 | `pure-value` | `haxe-domain` | `generic` 1, `interface` 1 |
| P2 | `mime` | 1 | `pure-value` | `haxe-domain` | `interface` 1, `multipleReturns` 1 |

## Highest-pressure APIs

This is a review projection. The compressed inventory retains every source locator, command profile, operation, effect, build profile, and normalized signature.

| Priority | Facade | Target API | Axes | Profiles | First source |
| --- | --- | --- | --- | --- | --- |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenSQL` | `callback`, `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/bootstrap.go:930` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/federation.go:295` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/federation.go:198` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/federation.go:314` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.Open` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/store_factory.go:110` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenForPreviewCommand` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/store_factory.go:291` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenForReadOnlyCommand` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/store_factory.go:101` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenForWorkingSetReconcile` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/store_factory.go:108` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenReadOnly` | `cgo`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/store_factory.go:297` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/embeddeddolt.OpenSQL` | `callback`, `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `portable-nocgo` | `cmd/bd/bootstrap.go:930` |
| P0 | `facade:storage-runtime` | `github.com/dolthub/driver/v2.NewConnector` | `cgo`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `release-cgo` | `internal/storage/embeddeddolt/open.go:45` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `cgo`, `context`, `interface`, `platformSpecific`, `pointer` | `release-cgo` | `cmd/bd/federation.go:414` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/dolt.New` | `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:201` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/dolt.NewFromConfig` | `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/doctor/fix/metadata.go:135` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage/dolt.NewFromConfigWithOptions` | `context`, `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/config_apply.go:286` |
| P0 | `facade:platform-runtime` | `context.WithTimeout` | `context`, `interface`, `multipleReturns`, `platformSpecific` | `portable-nocgo`, `release-cgo` | `internal/creds/command.go:119` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.Conn.BeginTx` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/storage/dolt/federation.go:595` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.Conn.QueryContext` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/storage/dolt/iter_dependents.go:96` |
| P0 | `facade:command-host` | `database/sql.*database/sql.DB.BeginTx` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/doctor/integrity.go:220` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.DB.BeginTx` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/migration/legacysqlite/reader.go:279` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.DB.Conn` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/storage/dbproxy/server/doltserver.go:397` |
| P0 | `facade:command-host` | `database/sql.*database/sql.DB.QueryContext` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/bootstrap.go:79` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.DB.QueryContext` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/doltserver/doltserver.go:1569` |
| P0 | `facade:storage-runtime` | `database/sql.*database/sql.Tx.QueryContext` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/migration/legacysqlite/reader.go:328` |
| P0 | `facade:command-host` | `database/sql.*database/sql.Tx.QueryContext` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/doctor/integrity.go:284` |
| P0 | `facade:storage-runtime` | `database/sql.OpenDB` | `cgo`, `interface`, `platformSpecific`, `pointer` | `release-cgo` | `internal/storage/embeddeddolt/open.go:50` |
| P0 | `facade:integration-runtime` | `github.com/anthropics/anthropic-sdk-go.github.com/anthropics/anthropic-sdk-go.MessageServ…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/compact/haiku.go:160` |
| P0 | `facade:command-host` | `github.com/anthropics/anthropic-sdk-go.github.com/anthropics/anthropic-sdk-go.MessageServ…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/find_duplicates.go:473` |
| P0 | `facade:storage-runtime` | `github.com/dolthub/driver/v2.ParseDSN` | `cgo`, `interface`, `multipleReturns`, `platformSpecific` | `release-cgo` | `internal/storage/embeddeddolt/open.go:35` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/ado.*github.com/steveyegge/beads/internal/ado.Reconc…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:625` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/configfile.Load` | `interface`, `multipleReturns`, `platformSpecific`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/backend_support.go:60` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/gitlab.*github.com/steveyegge/beads/internal/gitlab.…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/gitlab.go:687` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/linear.*github.com/steveyegge/beads/internal/linear.…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/linear.go:1329` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/linear.BuildLabelCacheFromTracker` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/linear.go:756` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/linear.BuildStateCacheFromTracker` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/linear.go:779` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/metrics.Init` | `callback`, `context`, `interface`, `multipleReturns` | `portable-nocgo`, `release-cgo` | `cmd/bd/main.go:929` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/migration/legacysqlite.Export` | `cgo`, `context`, `interface`, `platformSpecific` | `release-cgo` | `cmd/bd/legacy_sqlite_reader.go:24` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/molecules.*github.com/steveyegge/beads/internal/mole…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/main.go:1698` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/notion.*github.com/steveyegge/beads/internal/notion.…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/notion.go:655` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/notion.*github.com/steveyegge/beads/internal/notion.…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/notion.go:273` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/notion.*github.com/steveyegge/beads/internal/notion.…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/notion.go:285` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/notion.ResolveAuth` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/notion.go:191` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/notion.ResolveDataSourceReference` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/notion.go:676` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/dep.go:55` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/human.go:310` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/show_children.go:91` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/migrate_personal.go:159` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/graph.go:290` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/diff.go:45` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `cgo`, `context`, `interface`, `platformSpecific` | `release-cgo` | `cmd/bd/federation.go:317` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/list.go:313` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ready.go:309` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/export_auto.go:456` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/restore.go:64` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/delete.go:199` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/linear.go:1399` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/duplicates.go:59` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/delete.go:213` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/export_auto.go:455` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/delete.go:206` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/duplicates.go:399` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/epic.go:134` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/assign.go:96` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:904` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/comments.go:115` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/doctor/migration_validation.go:459` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ship.go:64` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/mol_last_activity.go:54` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/mol_current.go:108` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/close.go:270` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storestats/reporter.go:82` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/list_show_filter_modes.go:128` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storereader/reader.go:115` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ready.go:181` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/doctor_conventions.go:170` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storestats/reporter.go:46` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/auto_import_upgrade.go:98` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storestats/reporter.go:44` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/compact.go:315` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/compact.go:323` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/restore.go:115` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/migrate_personal.go:234` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/merge_slot.go:231` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/merge_slot.go:161` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/merge_slot.go:129` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/restore.go:77` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storestats/reporter.go:76` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:745` |
| P0 | `facade:http-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/workapi/storequerier/querier.go:56` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:812` |
| P0 | `facade:integration-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/gitlab/tracker.go:360` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/gitlab.go:812` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/linear.go:648` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/ado.go:771` |
| P0 | `facade:integration-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/notion/tracker.go:152` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/graph_apply.go:1215` |
| P0 | `facade:command-host` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/storage…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `cmd/bd/mol_port.go:102` |
| P0 | `facade:integration-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/tracker…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/tracker/engine.go:1511` |
| P0 | `facade:integration-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/tracker…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/tracker/engine.go:1472` |
| P0 | `facade:integration-runtime` | `github.com/steveyegge/beads/internal/storage.github.com/steveyegge/beads/internal/tracker…` | `context`, `interface`, `multipleReturns`, `pointer` | `portable-nocgo`, `release-cgo` | `internal/tracker/engine.go:1414` |

## Compiler disposition

The inventory links interface, context/handle, callback, channel, generic, cross-package, and multiple-return pressure to existing haxe.go gap owners. A handwritten boundary is not justified by preference alone: standard-library and independent third-party exported APIs require extern-first evidence, reusable compiler gaps must land in haxe.go before the BeadsHX lock advances, and first-party Beads code must be ported.

The historically named `test/native-pressure/simple_facade` tracer proves the minimum typed-boundary pipeline: authored Haxe calls one typed native API, generated Go passes native type checking, and runtime output is observed. It does not authorize a Go facade. Each real boundary must first use precise externs or record a reduced, framework-neutral reason that a native island remains necessary.

## Reproduce locally

```sh
npm run test:native-pressure
```

The command uses a temporary checkout of the pinned Git commit. It does not require GitHub or Docker and does not modify a live Beads database.
