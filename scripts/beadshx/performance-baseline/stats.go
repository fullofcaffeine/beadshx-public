package main

import (
	"fmt"
	"math"
	"sort"
)

type statistics struct {
	Count                  int     `json:"count"`
	Minimum                float64 `json:"minimum"`
	Maximum                float64 `json:"maximum"`
	Mean                   float64 `json:"mean"`
	Median                 float64 `json:"median"`
	P90                    float64 `json:"p90"`
	P95                    float64 `json:"p95"`
	StandardDeviation      float64 `json:"standardDeviation"`
	CoefficientOfVariation float64 `json:"coefficientOfVariation"`
	OutlierIndexes         []int   `json:"outlierIndexes"`
}

func summarize(values []float64, expectedCount int) (statistics, error) {
	if len(values) != expectedCount || len(values) < 2 {
		return statistics{}, fmt.Errorf("sample count = %d; want %d", len(values), expectedCount)
	}
	for index, value := range values {
		if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 {
			return statistics{}, fmt.Errorf("sample %d is invalid", index)
		}
	}
	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)
	var total float64
	for _, value := range sorted {
		total += value
	}
	mean := total / float64(len(sorted))
	var squaredDifference float64
	for _, value := range sorted {
		difference := value - mean
		squaredDifference += difference * difference
	}
	standardDeviation := math.Sqrt(squaredDifference / float64(len(sorted)-1))
	coefficient := 0.0
	if mean != 0 {
		coefficient = standardDeviation / mean
	}
	q1 := percentile(sorted, 25)
	q3 := percentile(sorted, 75)
	interquartileRange := q3 - q1
	lower := q1 - 1.5*interquartileRange
	upper := q3 + 1.5*interquartileRange
	outliers := make([]int, 0)
	for index, value := range values {
		if value < lower || value > upper {
			outliers = append(outliers, index)
		}
	}
	return statistics{
		Count:                  len(sorted),
		Minimum:                sorted[0],
		Maximum:                sorted[len(sorted)-1],
		Mean:                   mean,
		Median:                 percentile(sorted, 50),
		P90:                    percentile(sorted, 90),
		P95:                    percentile(sorted, 95),
		StandardDeviation:      standardDeviation,
		CoefficientOfVariation: coefficient,
		OutlierIndexes:         outliers,
	}, nil
}

func percentile(sorted []float64, percent float64) float64 {
	if len(sorted) == 1 {
		return sorted[0]
	}
	position := percent / 100 * float64(len(sorted)-1)
	lower := int(math.Floor(position))
	upper := int(math.Ceil(position))
	if lower == upper {
		return sorted[lower]
	}
	weight := position - float64(lower)
	return sorted[lower]*(1-weight) + sorted[upper]*weight
}
