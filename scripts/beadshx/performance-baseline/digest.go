package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func hashFile(path string) (string, int64, error) {
	file, err := os.Open(path) // #nosec G304 -- callers confine paths to reviewed roots.
	if err != nil {
		return "", 0, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", 0, err
	}
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(digest.Sum(nil)), info.Size(), nil
}

func canonicalJSONLDigest(content []byte) (string, error) {
	var records []string
	scanner := bufio.NewScanner(strings.NewReader(string(content)))
	scanner.Buffer(make([]byte, 64*1024), 16*1024*1024)
	for scanner.Scan() {
		if strings.TrimSpace(scanner.Text()) == "" {
			continue
		}
		var value any
		if err := json.Unmarshal(scanner.Bytes(), &value); err != nil {
			return "", fmt.Errorf("decode logical export: %w", err)
		}
		removeVolatileTimes(value)
		canonical, err := json.Marshal(value)
		if err != nil {
			return "", err
		}
		records = append(records, string(canonical))
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	if len(records) == 0 {
		return "", fmt.Errorf("logical export has no records")
	}
	sort.Strings(records)
	return digestBytes([]byte(strings.Join(records, "\n") + "\n")), nil
}

func removeVolatileTimes(value any) {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			if strings.HasSuffix(key, "_at") || key == "timestamp" {
				delete(typed, key)
				continue
			}
			removeVolatileTimes(child)
		}
	case []any:
		for _, child := range typed {
			removeVolatileTimes(child)
		}
	}
}

func hashDirectory(root string) (string, int64, error) {
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type().IsRegular() {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return "", 0, err
	}
	sort.Strings(paths)
	digest := sha256.New()
	var total int64
	for _, path := range paths {
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return "", 0, err
		}
		fileDigest, size, err := hashFile(path)
		if err != nil {
			return "", 0, err
		}
		total += size
		if _, err := fmt.Fprintf(digest, "%s\x00%d\x00%s\n", filepath.ToSlash(relative), size, fileDigest); err != nil {
			return "", 0, err
		}
	}
	return hex.EncodeToString(digest.Sum(nil)), total, nil
}
