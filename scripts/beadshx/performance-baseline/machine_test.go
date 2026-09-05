package main

import "testing"

func TestFieldValueSelectsExactMachineField(t *testing.T) {
	content := "   Solid State:               Yes\n   File System Personality:   APFS\n"
	if actual := fieldValue(content, "File System Personality"); actual != "APFS" {
		t.Fatalf("fieldValue() = %q; want APFS", actual)
	}
	if actual := fieldValue(content, "State"); actual != "" {
		t.Fatalf("fieldValue() accepted partial field name: %q", actual)
	}
}
