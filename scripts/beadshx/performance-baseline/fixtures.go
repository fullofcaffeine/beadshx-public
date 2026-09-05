package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type fixtureIssue struct {
	ID           string              `json:"id"`
	Title        string              `json:"title"`
	Description  string              `json:"description"`
	Status       string              `json:"status"`
	Priority     int                 `json:"priority"`
	IssueType    string              `json:"issue_type"`
	CreatedAt    time.Time           `json:"created_at"`
	UpdatedAt    time.Time           `json:"updated_at"`
	Labels       []string            `json:"labels,omitempty"`
	Dependencies []fixtureDependency `json:"dependencies,omitempty"`
	Comments     []fixtureComment    `json:"comments,omitempty"`
}

type fixtureDependency struct {
	DependsOnID string    `json:"depends_on_id"`
	Type        string    `json:"type"`
	CreatedAt   time.Time `json:"created_at"`
	CreatedBy   string    `json:"created_by"`
}

type fixtureComment struct {
	ID        string    `json:"id"`
	IssueID   string    `json:"issue_id"`
	Author    string    `json:"author"`
	Text      string    `json:"text"`
	CreatedAt time.Time `json:"created_at"`
}

type fixtureManifest struct {
	SchemaVersion     int           `json:"schemaVersion"`
	Fixture           fixturePolicy `json:"fixture"`
	ContentFile       string        `json:"contentFile"`
	ContentSHA256     string        `json:"contentSha256"`
	ContentBytes      int           `json:"contentBytes"`
	GeneratedIssueIDs []string      `json:"generatedIssueIds"`
}

func generateFixtures(outputDirectory string, selected policy) error {
	if err := os.MkdirAll(outputDirectory, 0o755); err != nil {
		return err
	}
	for _, fixture := range selected.Fixtures {
		content, ids, err := generateFixture(fixture)
		if err != nil {
			return fmt.Errorf("fixture %s: %w", fixture.ID, err)
		}
		digest := sha256.Sum256(content)
		manifest := fixtureManifest{
			SchemaVersion:     1,
			Fixture:           fixture,
			ContentFile:       fixture.ID + ".jsonl",
			ContentSHA256:     hex.EncodeToString(digest[:]),
			ContentBytes:      len(content),
			GeneratedIssueIDs: []string{ids[0], ids[len(ids)/2], ids[len(ids)-1]},
		}
		manifestContent, err := json.MarshalIndent(manifest, "", "  ")
		if err != nil {
			return err
		}
		manifestContent = append(manifestContent, '\n')
		if err := writeFile(filepath.Join(outputDirectory, fixture.ID+".jsonl"), content); err != nil {
			return err
		}
		if err := writeFile(filepath.Join(outputDirectory, fixture.ID+".manifest.json"), manifestContent); err != nil {
			return err
		}
	}
	return nil
}

func generateFixture(selected fixturePolicy) ([]byte, []string, error) {
	if selected.IssueCount < 1 || len(selected.TextDistributionBytes) == 0 {
		return nil, nil, fmt.Errorf("invalid fixture dimensions")
	}
	prefix := "perf-s"
	if selected.IssueCount > 100 {
		prefix = "perf-l"
	}
	ids := make([]string, selected.IssueCount)
	for index := range ids {
		ids[index] = fmt.Sprintf("%s-%05d", prefix, index+1)
	}

	baseTime := time.Date(2026, time.August, 20, 12, 0, 0, 0, time.UTC)
	var output bytes.Buffer
	encoder := json.NewEncoder(&output)
	for index, id := range ids {
		textBytes := selected.TextDistributionBytes[(index+int(selected.Seed%int64(len(selected.TextDistributionBytes))))%len(selected.TextDistributionBytes)]
		issue := fixtureIssue{
			ID:          id,
			Title:       fmt.Sprintf("Performance fixture issue %05d", index+1),
			Description: deterministicText(textBytes, index),
			Status:      "open",
			Priority:    index % 5,
			IssueType:   "task",
			CreatedAt:   baseTime.Add(time.Duration(index) * time.Second),
			UpdatedAt:   baseTime.Add(time.Duration(index) * time.Second),
		}
		if index%5 == 4 {
			issue.Status = "closed"
		}
		if index < selected.LabelCount {
			issue.Labels = []string{fmt.Sprintf("fixture-label-%02d", index%16)}
		}
		if index > 0 && index <= selected.DependencyCount {
			targetIndex := dependencyTarget(index, selected.IssueCount)
			issue.Dependencies = []fixtureDependency{{
				DependsOnID: ids[targetIndex],
				Type:        "blocks",
				CreatedAt:   issue.CreatedAt,
				CreatedBy:   "fixture-generator",
			}}
		}
		if index < selected.CommentCount {
			issue.Comments = []fixtureComment{{
				ID:        fmt.Sprintf("fixture-comment-%05d", index+1),
				IssueID:   id,
				Author:    "fixture-generator",
				Text:      fmt.Sprintf("Deterministic fixture comment %05d", index+1),
				CreatedAt: issue.CreatedAt,
			}}
		}
		if err := encoder.Encode(issue); err != nil {
			return nil, nil, err
		}
	}
	return output.Bytes(), ids, nil
}

func dependencyTarget(index, issueCount int) int {
	if issueCount <= 100 {
		if index >= 4 {
			return index - 4
		}
		return 0
	}
	if index == 0 {
		return 0
	}
	return (index - 1) / 2
}

func deterministicText(length, index int) string {
	seed := fmt.Sprintf("fixture-%05d-", index+1)
	repetitions := length/len(seed) + 1
	return strings.Repeat(seed, repetitions)[:length]
}

func writeFile(path string, content []byte) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".performance-baseline-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	if _, err := temporary.Write(content); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	// #nosec G302 -- generated repository evidence must be readable by reviewers.
	if err := os.Chmod(temporaryPath, 0o644); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}
