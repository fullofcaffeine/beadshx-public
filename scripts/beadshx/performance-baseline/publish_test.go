package main

import "testing"

func TestEqualPortableSummaryAllowsArchitectureRounding(t *testing.T) {
	left := statistics{Count: 10, StandardDeviation: 55313254.7411289}
	right := left
	right.StandardDeviation += 0.00001
	if !equalPortableSummary(left, right) {
		t.Fatal("expected insignificant floating-point drift to compare equal")
	}
}

func TestEqualPortableSummaryRejectsMaterialChange(t *testing.T) {
	left := statistics{Count: 10, Mean: 100}
	right := left
	right.Mean = 101
	if equalPortableSummary(left, right) {
		t.Fatal("expected a material summary change to compare unequal")
	}
}

func TestEqualPortableSummaryKeepsIdentityExact(t *testing.T) {
	left := runSummary{RunID: "first"}
	right := runSummary{RunID: "second"}
	if equalPortableSummary(left, right) {
		t.Fatal("expected evidence identity to compare exactly")
	}
}
