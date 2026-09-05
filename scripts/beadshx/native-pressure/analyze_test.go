package main

import (
	"go/importer"
	"go/token"
	"go/types"
	"reflect"
	"testing"

	"golang.org/x/tools/go/packages"
)

func TestSignatureAxesStayAtTheBoundarySurface(t *testing.T) {
	errorType := types.Universe.Lookup("error").Type()
	signature := testSignature(nil, []types.Type{errorType})

	actual := signatureAxes(signature)
	expected := map[string]bool{"interface": true}
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("error result axes = %#v; want %#v", actual, expected)
	}
}

func TestSignatureAxesClassifyDirectPressure(t *testing.T) {
	contextPackage, err := importer.Default().Import("context")
	if err != nil {
		t.Fatal(err)
	}
	contextType := contextPackage.Scope().Lookup("Context").Type()
	callback := testSignature([]types.Type{types.Typ[types.String]}, []types.Type{types.Typ[types.Bool]})
	channel := types.NewChan(types.SendRecv, types.Typ[types.String])
	signature := testSignature(
		[]types.Type{contextType, callback, channel, types.NewPointer(types.Typ[types.Int])},
		[]types.Type{types.Typ[types.String], types.Universe.Lookup("error").Type()},
	)

	actual := signatureAxes(signature)
	for _, axis := range []string{"callback", "channel", "context", "interface", "multipleReturns", "pointer"} {
		if !actual[axis] {
			t.Errorf("missing axis %s in %#v", axis, actual)
		}
	}
	if actual["generic"] {
		t.Errorf("unexpected generic axis in %#v", actual)
	}
}

func TestDependencyPolicyUsesFirstMatch(t *testing.T) {
	policies, err := compileDependencyPolicies([]dependencyPolicy{
		{ID: "specific", PackageRegex: "^net/http$"},
		{ID: "fallback", PackageRegex: ".*"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if actual := selectDependencyPolicy("net/http", policies).ID; actual != "specific" {
		t.Fatalf("policy = %q; want specific", actual)
	}
}

func TestPackageErrorsOnlyAdmitsExpectedExternalCGODiagnostics(t *testing.T) {
	tests := []struct {
		name        string
		packagePath string
		message     string
		wantError   bool
	}{
		{name: "runtime cgo", packagePath: "runtime/cgo", message: "missing native metadata"},
		{name: "external import C", packagePath: "github.com/example/sqlite", message: "could not import C (no metadata for C)", wantError: false},
		{name: "first party import C", packagePath: "github.com/steveyegge/beads/internal/storage", message: "could not import C (no metadata for C)", wantError: true},
		{name: "unrelated external error", packagePath: "github.com/example/sdk", message: "undefined: Client", wantError: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			selected := &packages.Package{
				ID:      test.packagePath,
				PkgPath: test.packagePath,
				Errors:  []packages.Error{{Msg: test.message}},
			}
			err := packageErrors([]*packages.Package{selected}, "github.com/steveyegge/beads/", true)
			if (err != nil) != test.wantError {
				t.Fatalf("packageErrors() error = %v; wantError = %t", err, test.wantError)
			}
		})
	}
}

func testSignature(parameters, results []types.Type) *types.Signature {
	return types.NewSignatureType(
		nil,
		nil,
		nil,
		testTuple(parameters),
		testTuple(results),
		false,
	)
}

func testTuple(selectedTypes []types.Type) *types.Tuple {
	variables := make([]*types.Var, 0, len(selectedTypes))
	for _, selectedType := range selectedTypes {
		variables = append(variables, types.NewVar(token.NoPos, nil, "", selectedType))
	}
	return types.NewTuple(variables...)
}
