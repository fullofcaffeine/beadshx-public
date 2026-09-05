package main

import (
	"reflect"
	"testing"
)

func TestReplaceEnvironmentChangesOnlyExactName(t *testing.T) {
	input := []string{"GOCACHE=/old", "NOT_GOCACHE=keep", "PATH=/bin"}
	actual := replaceEnvironment(input, "GOCACHE", "/new")
	expected := []string{"GOCACHE=/new", "NOT_GOCACHE=keep", "PATH=/bin"}
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("replaceEnvironment() = %#v; want %#v", actual, expected)
	}
}
