package main

import "testing"

func TestSetDifferenceIsSortedAndDirectional(t *testing.T) {
	t.Parallel()
	left, right := setDifference([]string{"c", "a", "b"}, []string{"d", "b"})
	if !equalStrings(left, []string{"a", "c"}) || !equalStrings(right, []string{"d"}) {
		t.Fatalf("unexpected difference: left=%v right=%v", left, right)
	}
}

func TestActivationMatrixRejectsExtraTransientSurface(t *testing.T) {
	t.Parallel()
	snapshots := syntheticMatrix()
	snapshots[0].Commands = append(snapshots[0].Commands, commandRecord{ID: "cmd:bd/unreviewed"})
	if err := checkProfileAndActivationMatrix(snapshots); err == nil {
		t.Fatal("activation matrix accepted an unreviewed completion-only command")
	}
}

func syntheticMatrix() []runtimeSnapshot {
	federationChildren := []commandRecord{
		{ID: "cmd:bd/federation/add-peer"},
		{ID: "cmd:bd/federation/list-peers"},
		{ID: "cmd:bd/federation/remove-peer"},
		{ID: "cmd:bd/federation/status"},
		{ID: "cmd:bd/federation/sync"},
	}
	federationFlags := []flagDeclaration{
		{ID: "flag:cmd:bd/federation/add-peer/--help"},
		{ID: "flag:cmd:bd/federation/add-peer/--password"},
		{ID: "flag:cmd:bd/federation/add-peer/--sovereignty"},
		{ID: "flag:cmd:bd/federation/add-peer/--user"},
		{ID: "flag:cmd:bd/federation/list-peers/--help"},
		{ID: "flag:cmd:bd/federation/remove-peer/--help"},
		{ID: "flag:cmd:bd/federation/status/--help"},
		{ID: "flag:cmd:bd/federation/status/--peer"},
		{ID: "flag:cmd:bd/federation/sync/--help"},
		{ID: "flag:cmd:bd/federation/sync/--peer"},
		{ID: "flag:cmd:bd/federation/sync/--strategy"},
	}
	baseCommands := []commandRecord{{ID: "cmd:bd"}, {ID: "cmd:bd/federation"}}
	portableNormal := runtimeSnapshot{Profile: "portable-nocgo", Activation: "normal", Commands: append([]commandRecord(nil), baseCommands...)}
	portableCompletion := portableNormal
	portableCompletion.Activation = "completion"
	portableCompletion.Commands = append(append([]commandRecord(nil), baseCommands...), commandRecord{ID: "cmd:bd/__complete"})
	portableCompletion.Flags = []flagDeclaration{{ID: "flag:cmd:bd/__complete/--help"}}
	releaseNormal := runtimeSnapshot{Profile: "release-cgo", Activation: "normal", Commands: append(append([]commandRecord(nil), baseCommands...), federationChildren...), Flags: federationFlags}
	releaseCompletion := releaseNormal
	releaseCompletion.Activation = "completion"
	releaseCompletion.Commands = append(append([]commandRecord(nil), releaseNormal.Commands...), commandRecord{ID: "cmd:bd/__complete"})
	releaseCompletion.Flags = append(append([]flagDeclaration(nil), federationFlags...), flagDeclaration{ID: "flag:cmd:bd/__complete/--help"})
	return []runtimeSnapshot{portableCompletion, portableNormal, releaseCompletion, releaseNormal}
}
