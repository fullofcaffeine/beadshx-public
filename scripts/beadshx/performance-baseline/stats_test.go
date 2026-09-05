package main

import (
	"math"
	"reflect"
	"testing"
)

func TestSummarizeRetainsVarianceAndOutliers(t *testing.T) {
	values := []float64{1, 2, 3, 4, 5, 6, 7, 8, 9, 100}
	actual, err := summarize(values, 10)
	if err != nil {
		t.Fatal(err)
	}
	if actual.Count != 10 || actual.Minimum != 1 || actual.Maximum != 100 || actual.Median != 5.5 {
		t.Fatalf("unexpected statistics: %#v", actual)
	}
	if actual.StandardDeviation <= 0 || actual.CoefficientOfVariation <= 0 || !reflect.DeepEqual(actual.OutlierIndexes, []int{9}) {
		t.Fatalf("variance or outlier evidence missing: %#v", actual)
	}
	if math.Abs(actual.P90-18.1) > 0.0001 || math.Abs(actual.P95-59.05) > 0.0001 {
		t.Fatalf("unexpected percentiles: p90=%f p95=%f", actual.P90, actual.P95)
	}
}

func TestSummarizeRejectsMissingSamples(t *testing.T) {
	if _, err := summarize([]float64{1, 2}, 10); err == nil {
		t.Fatal("summarize() accepted missing samples")
	}
}
