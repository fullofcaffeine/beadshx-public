package main

import "testing"

func TestSummarizeRecordsRejectsIndexDrift(t *testing.T) {
	records := make([]sampleRecord, 10)
	for index := range records {
		records[index] = sampleRecord{
			WorkloadID: "work", SampleIndex: index, Validation: "pass", ObservedSHA256: "observed",
			Measurement: processMeasurement{ExitCode: 0, MemoryObserverAvailable: true, ElapsedNanoseconds: 1, UserNanoseconds: 1, SystemNanoseconds: 1, MaximumResidentBytes: 1, StdoutSHA256: "output"},
		}
	}
	records[3].SampleIndex = 4
	if _, _, _, err := summarizeRecords("work", records, 10); err == nil {
		t.Fatal("summarizeRecords() accepted sample index drift")
	}
}

func TestSummarizeRecordsAcceptsValidatedSyncConflictExit(t *testing.T) {
	records := make([]sampleRecord, 10)
	for index := range records {
		records[index] = sampleRecord{
			WorkloadID: "sync-conflict", SampleIndex: index, Validation: "halted", ObservedSHA256: "remote",
			Measurement: processMeasurement{ExitCode: 2, MemoryObserverAvailable: true, ElapsedNanoseconds: 1, UserNanoseconds: 1, SystemNanoseconds: 1, MaximumResidentBytes: 1, StdoutSHA256: "output"},
		}
	}
	if _, _, _, err := summarizeRecords("sync-conflict", records, 10); err != nil {
		t.Fatal(err)
	}
}
