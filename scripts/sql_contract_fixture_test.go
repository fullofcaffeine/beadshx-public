package scripts_test

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

func TestSQLContractsUseIsolatedBuildInputs(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("repository shell contract")
	}
	for _, tool := range []string{"bash", "git", "python3"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("requires %s", tool)
		}
	}
	for _, mode := range []string{"success", "compile_failure", "reordered_observations", "truncated_observations", "wrong_type_observations", "embedded_success", "embedded_compile_failure", "embedded_test_failure", "scalar_success", "scalar_compile_failure", "scalar_test_failure"} {
		t.Run(mode, func(t *testing.T) {
			embedded := strings.HasPrefix(mode, "embedded_")
			scalar := strings.HasPrefix(mode, "scalar_")
			fail := mode != "success" && mode != "embedded_success" && mode != "scalar_success"
			parent := t.TempDir()
			source := filepath.Join(parent, "source")
			bin := filepath.Join(parent, "bin")
			write := func(path, text string, mode os.FileMode) {
				t.Helper()
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(text), mode); err != nil {
					t.Fatal(err)
				}
			}
			for _, name := range []string{"test-sql-error-contracts.sh", "assert-disposable-workspace.sh"} {
				data, err := os.ReadFile(filepath.Join("beadshx", name))
				if err != nil {
					t.Fatal(err)
				}
				write(filepath.Join(source, "scripts/beadshx", name), string(data), 0755)
			}
			inputs := map[string]string{"upstream/locks/haxe-go.json": "compiler pin\n", "go.mod": "module fixture\n", "go.sum": "sum input\n", ".haxerc": "scoped configuration\n", "LICENSE": "authored license\n", ".buildflags": "-tags=gms_pure_go\n", "engdocs/beadshx/program/toolchain-locks.json": "locked toolchain\n", "internal/storage/schema/migrations/one.up.sql": "embedded migration\n", "src/space and\nnewline.hx": "authored source\n"}
			for _, name := range []string{"storage_errors", "storage_relation_errors", "storage_summary_errors", "render_metadata", "raw_metadata_output", "nullable_issue_strings", "native_issue_math", "sql_comment_reader", "sql_comment_details", "server_driver_timeouts", "complete_issue_row", "embedded_comment_details", "scalar_label_details"} {
				inputs["test/"+name+"/compile.hxml"] = "contract " + name + "\n"
			}
			inputs["test/complete_issue_row/native_test.go.in"] = "package main // authored observer\n"
			inputs["test/embedded_comment_details/native_test.go.in"] = "package main // embedded observer\n"
			inputs["test/scalar_label_details/native_test.go.in"] = "package main // scalar labels observer\n"
			for rel, data := range inputs {
				write(filepath.Join(source, rel), data, 0644)
			}
			write(filepath.Join(source, ".gitignore"), ".buildflags\nprivate.env\nnode_modules/\n.toolchains/\n", 0644)
			write(filepath.Join(source, "private.env"), "must not copy", 0600)
			write(filepath.Join(source, ".playwright-mcp/console.log"), "local browser diagnostic sentinel", 0600)
			write(filepath.Join(source, ".beads/primary"), "database sentinel", 0600)
			write(filepath.Join(source, "generated/root-sentinel"), "generated sentinel", 0644)
			write(filepath.Join(source, "LICENSES/generated-license"), "unowned generated license", 0644)
			for _, dep := range []string{"node_modules", ".toolchains/haxe.go"} {
				write(filepath.Join(source, dep, "sentinel"), "dependency sentinel", 0644)
			}
			for _, args := range [][]string{{"init", "-q"}, {"add", "."}} {
				cmd := exec.Command("git", args...)
				cmd.Dir = source
				if out, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("git: %v %s", err, out)
				}
			}
			// Newly authored, untracked inputs must be included too.
			inputs["src/new-input.hx"] = "untracked source\n"
			write(filepath.Join(source, "src/new-input.hx"), inputs["src/new-input.hx"], 0644)
			manifest, _ := json.Marshal(inputs)
			manifestPath := filepath.Join(parent, "inputs.json")
			write(manifestPath, string(manifest), 0644)
			probe := filepath.Join(parent, "probe.py")
			write(probe, `import json,os,pathlib,sys
cwd=pathlib.Path.cwd(); source=pathlib.Path(os.environ['SQL_SOURCE']).resolve()
assert cwd != source and (cwd/'.beadshx-disposable-fixture').is_file()
assert not (cwd/'.git').exists() and not (cwd/'.beads').exists() and not (cwd/'private.env').exists()
assert not (cwd/'.playwright-mcp').exists()
assert not (cwd/'generated/root-sentinel').exists() and not (cwd/'LICENSES/generated-license').exists()
for rel,value in json.loads(pathlib.Path(os.environ['SQL_INPUTS']).read_text()).items(): assert (cwd/rel).read_text()==value,rel
for dep in ['node_modules','.toolchains/haxe.go']: assert (cwd/dep).resolve()==source/dep
assert os.environ['GOWORK']=='off'
for key in ['BEADS_DB','BEADS_DIR','BD_DB','GT_ROOT','GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE']: assert key not in os.environ,key
name=pathlib.Path(sys.argv[1]).name
if name=='jq': print('go1.26.11'); sys.exit(0)
with open(os.environ['SQL_LOG'],'a') as out: out.write(json.dumps({'cwd':str(cwd),'tool':name,'args':sys.argv[2:]})+'\n')
if name=='npx':
 assert sys.argv[2:4]==['--no-install','haxe']
 (cwd/'generated/go/bdhx').mkdir(parents=True,exist_ok=True)
 (cwd/'generated/fixture-output').write_text('disposable')
 if os.environ['SQL_MODE'] in ['compile_failure','embedded_compile_failure','scalar_compile_failure']: sys.exit(23)
if name=='go':
 args=sys.argv[2:]
 if args in [['env','GOMODCACHE'],['env','GOCACHE']]:
  assert os.environ['SQL_MODE'].startswith('embedded_')
  print(str(source/('module-cache' if args[1]=='GOMODCACHE' else 'build-cache')))
  sys.exit(0)
 observer=cwd/'generated/go/bdhx/complete_row_test.go'
 calls=[json.loads(line) for line in pathlib.Path(os.environ['SQL_LOG']).read_text().splitlines()]
 last_compile=next(call for call in reversed(calls) if call['tool']=='npx')
 if 'test/complete_issue_row/compile.hxml' in last_compile['args']:
  assert observer.read_bytes()==(cwd/'test/complete_issue_row/native_test.go.in').read_bytes()
 else: assert not observer.exists()
 contract=pathlib.Path(last_compile['args'][2]).parent.name
 embedded_observer=cwd/'generated/go/bdhx/embedded_comment_test.go'
 if contract=='embedded_comment_details':
  assert embedded_observer.read_bytes()==(cwd/'test/embedded_comment_details/native_test.go.in').read_bytes()
  assert os.environ['CGO_ENABLED']=='1'
  assert pathlib.Path(os.environ['HOME']).samefile(cwd/'home') and pathlib.Path(os.environ['USERPROFILE']).samefile(cwd/'home')
  assert pathlib.Path(os.environ['XDG_CONFIG_HOME']).samefile(cwd/'config') and (cwd/'config').is_dir()
  assert os.environ['GIT_CONFIG_NOSYSTEM']=='1' and pathlib.Path(os.environ['GIT_CONFIG_GLOBAL']).resolve()==cwd/'gitconfig'
  assert os.environ['GOMODCACHE']==str(source/'module-cache') and os.environ['GOCACHE']==str(source/'build-cache')
  assert args==['test','-tags=gms_pure_go','-run','^TestEmbeddedCommentDetails$','-count=1','-timeout=300s','./generated/go/bdhx']
  if os.environ['SQL_MODE']=='embedded_test_failure': sys.exit(29)
 else: assert not embedded_observer.exists()
 scalar_observer=cwd/'generated/go/bdhx/scalar_label_test.go'
 if contract=='scalar_label_details':
  assert scalar_observer.read_bytes()==(cwd/'test/scalar_label_details/native_test.go.in').read_bytes()
  assert os.environ['CGO_ENABLED']=='1'
  assert args==['test','-tags=gms_pure_go','-run','^TestScalarLabelAssembly$','-count=1','-timeout=300s','./generated/go/bdhx']
  if os.environ['SQL_MODE']=='scalar_test_failure': sys.exit(29)
 else: assert not scalar_observer.exists()
 if './test/sql_comment_reader' in args:
  key='BEADSHX_COMMENT_OBSERVATIONS' if '^TestPinnedCommentReadObserver$' in args else 'BEADSHX_COMMENT_DETAIL_OBSERVATIONS'
  target=pathlib.Path(os.environ[key]); assert target.parent.resolve()==cwd and not target.exists()
  count=21 if key=='BEADSHX_COMMENT_OBSERVATIONS' else 25
  target.write_text(''.join(json.dumps({'name':str(i),'count':0})+'\n' for i in range(count)))
 if args[0]=='run' and contract in ['sql_comment_reader','sql_comment_details']:
  count=21 if contract=='sql_comment_reader' else 25
  rows=[{'name':str(i),'count':0} for i in range(count)]
  if contract=='sql_comment_reader':
   if os.environ['SQL_MODE']=='reordered_observations': rows[0],rows[1]=rows[1],rows[0]
   if os.environ['SQL_MODE']=='truncated_observations': rows.pop()
   if os.environ['SQL_MODE']=='wrong_type_observations': rows[0]['count']=False
  for row in rows: print(json.dumps(row))
`, 0644)
			for _, tool := range []string{"npx", "go", "jq"} {
				write(filepath.Join(bin, tool), "#!/usr/bin/env bash\nexec python3 \"$SQL_PROBE\" \"$0\" \"$@\"\n", 0755)
			}
			log := filepath.Join(parent, "calls.jsonl")
			cmd := exec.Command("bash", filepath.Join(source, "scripts/beadshx/test-sql-error-contracts.sh"))
			if embedded {
				cmd.Args = append(cmd.Args, "--embedded-comments")
			} else if scalar {
				cmd.Args = append(cmd.Args, "--scalar-labels")
			}
			cmd.Env = append(os.Environ(), "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"), "TMPDIR="+parent, "SQL_PROBE="+probe, "SQL_SOURCE="+source, "SQL_INPUTS="+manifestPath, "SQL_LOG="+log, "SQL_MODE="+mode, "GOWORK=/must-not-use/ambient.go.work", "BEADS_DB=/must-not-open/primary", "BEADS_DIR=/must-not-open", "BD_DB=/must-not-open/legacy", "GT_ROOT=/must-not-open/root", "GIT_DIR=/must-not-open/git", "GIT_WORK_TREE=/must-not-open/worktree", "GIT_INDEX_FILE=/must-not-open/index")
			out, err := cmd.CombinedOutput()
			if fail {
				wantExit := 1
				if mode == "compile_failure" || mode == "embedded_compile_failure" || mode == "scalar_compile_failure" {
					wantExit = 23
				} else if mode == "embedded_test_failure" || mode == "scalar_test_failure" {
					wantExit = 29
				}
				if e, ok := err.(*exec.ExitError); !ok || e.ExitCode() != wantExit {
					t.Fatalf("expected exit%d: %v %s", wantExit, err, out)
				}
			} else if err != nil {
				t.Fatalf("wrapper: %v %s", err, out)
			}
			data, err := os.ReadFile(log)
			if err != nil {
				t.Fatalf("log: %v %s", err, out)
			}
			type invocation struct {
				Cwd  string
				Tool string
				Args []string
			}
			var records []invocation
			for _, line := range bytes.Split(bytes.TrimSpace(data), []byte("\n")) {
				var record invocation
				if err := json.Unmarshal(line, &record); err != nil {
					t.Fatal(err)
				}
				records = append(records, record)
			}
			want := 35
			if embedded {
				want = 4
			} else if scalar {
				want = 2
			}
			if mode == "compile_failure" || mode == "embedded_compile_failure" || mode == "scalar_compile_failure" {
				want = 1
			} else if fail && !embedded && !scalar {
				want = 25
			}
			if len(records) != want {
				t.Fatalf("dispatch count=%d want%d", len(records), want)
			}
			fixture := records[0].Cwd
			var expected []invocation
			contracts := []string{"storage_errors", "storage_relation_errors", "storage_summary_errors", "render_metadata", "raw_metadata_output", "nullable_issue_strings", "native_issue_math", "sql_comment_reader", "sql_comment_details", "server_driver_timeouts", "complete_issue_row"}
			if embedded {
				contracts = []string{"embedded_comment_details"}
			} else if scalar {
				contracts = []string{"scalar_label_details"}
			}
			for _, contract := range contracts {
				if contract == "embedded_comment_details" {
					expected = append(expected, invocation{fixture, "npx", []string{"--no-install", "haxe", "test/embedded_comment_details/compile.hxml", "-D", "go_no_build"}}, invocation{fixture, "go", []string{"env", "GOMODCACHE"}}, invocation{fixture, "go", []string{"env", "GOCACHE"}}, invocation{fixture, "go", []string{"test", "-tags=gms_pure_go", "-run", "^TestEmbeddedCommentDetails$", "-count=1", "-timeout=300s", "./generated/go/bdhx"}})
					continue
				}
				if contract == "scalar_label_details" {
					expected = append(expected, invocation{fixture, "npx", []string{"--no-install", "haxe", "test/scalar_label_details/compile.hxml", "-D", "go_no_build"}}, invocation{fixture, "go", []string{"test", "-tags=gms_pure_go", "-run", "^TestScalarLabelAssembly$", "-count=1", "-timeout=300s", "./generated/go/bdhx"}})
					continue
				}
				expected = append(expected, invocation{fixture, "npx", []string{"--no-install", "haxe", "test/" + contract + "/compile.hxml", "-D", "go_no_build"}}, invocation{fixture, "go", []string{"test", "-tags=gms_pure_go", "./generated/go/bdhx"}})
				if contract == "sql_comment_reader" || contract == "sql_comment_details" {
					test := "^TestPinnedCommentReadObserver$"
					if contract == "sql_comment_details" {
						test = "^TestPinnedCommentDetailObserver$"
					}
					expected = append(expected, invocation{fixture, "go", []string{"test", "-tags=gms_pure_go", "./test/sql_comment_reader", "-run", test, "-count=1"}})
				}
				expected = append(expected, invocation{fixture, "go", []string{"run", "-tags=gms_pure_go", "./generated/go/bdhx"}})
			}
			expected = expected[:want]
			if !reflect.DeepEqual(records, expected) {
				t.Fatalf("dispatch mismatch: got%+v want%+v", records, expected)
			}
			_, statErr := os.Stat(fixture)
			if fail && statErr != nil {
				t.Fatal("failed fixture not retained")
			}
			if !fail && !os.IsNotExist(statErr) {
				t.Fatal("successful fixture not cleaned")
			}
			for rel, want := range map[string]string{"generated/root-sentinel": "generated sentinel", ".beads/primary": "database sentinel", "node_modules/sentinel": "dependency sentinel", ".toolchains/haxe.go/sentinel": "dependency sentinel"} {
				data, err := os.ReadFile(filepath.Join(source, rel))
				if err != nil || string(data) != want {
					t.Fatalf("source changed: %s", rel)
				}
			}
		})
	}
}

func TestSQLContractsRejectArgumentsBeforeFixtureCreation(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("repository shell contract")
	}
	for _, args := range [][]string{{""}, {"--unexpected"}, {"--embedded-comments", "extra"}, {"--scalar-labels", "extra"}, {"--scalar-labels", "--embedded-comments"}} {
		t.Run(strings.Join(args, "_"), func(t *testing.T) {
			parent := t.TempDir()
			bin := filepath.Join(parent, "bin")
			if err := os.Mkdir(bin, 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(bin, "mktemp"), []byte("#!/usr/bin/env bash\nprintf called >\"$SQL_UNEXPECTED_MKTEMP\"\nexit 91\n"), 0755); err != nil {
				t.Fatal(err)
			}
			sentinel := filepath.Join(parent, "mktemp-called")
			command := exec.Command("bash", append([]string{"beadshx/test-sql-error-contracts.sh"}, args...)...)
			command.Env = append(os.Environ(), "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"), "SQL_UNEXPECTED_MKTEMP="+sentinel)
			out, err := command.CombinedOutput()
			if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 2 {
				t.Fatalf("invalid arguments must exit2: %v %s", err, out)
			}
			if !bytes.Contains(out, []byte("usage:")) {
				t.Fatalf("missing usage diagnostic: %s", out)
			}
			if _, err := os.Stat(sentinel); !os.IsNotExist(err) {
				t.Fatal("invalid arguments reached fixture creation")
			}
		})
	}
}
