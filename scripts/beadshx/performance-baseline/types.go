package main

type policy struct {
	SchemaVersion    int               `json:"schemaVersion"`
	Source           sourcePolicy      `json:"source"`
	ServerToolchain  serverToolchain   `json:"serverToolchain"`
	Sample           samplePolicy      `json:"samplePolicy"`
	FixedEnvironment map[string]string `json:"fixedEnvironment"`
	Profiles         []profilePolicy   `json:"profiles"`
	Fixtures         []fixturePolicy   `json:"fixtures"`
	Workloads        []workloadPolicy  `json:"workloads"`
}

type serverToolchain struct {
	Version                  string `json:"version"`
	RepositoryRelativeBinary string `json:"repositoryRelativeBinary"`
	DarwinArm64ArchiveSHA256 string `json:"darwinArm64ArchiveSha256"`
	DarwinArm64BinarySHA256  string `json:"darwinArm64BinarySha256"`
}

type sourcePolicy struct {
	Project string `json:"project"`
	Version string `json:"version"`
	Commit  string `json:"commit"`
}

type samplePolicy struct {
	SetupRuns               int      `json:"setupRuns"`
	MeasuredRuns            int      `json:"measuredRuns"`
	MicrobenchmarkCount     int      `json:"microbenchmarkCount"`
	MicrobenchmarkBenchtime string   `json:"microbenchmarkBenchtime"`
	OutlierRule             string   `json:"outlierRule"`
	RequiredStatistics      []string `json:"requiredStatistics"`
}

type profilePolicy struct {
	ID         string   `json:"id"`
	Kind       string   `json:"kind"`
	GOOS       string   `json:"goos"`
	GOARCH     string   `json:"goarch"`
	CGOEnabled bool     `json:"cgoEnabled"`
	BuildTags  []string `json:"buildTags"`
	Admission  string   `json:"admission"`
}

type fixturePolicy struct {
	ID                    string `json:"id"`
	GeneratorRevision     int    `json:"generatorRevision"`
	Seed                  int64  `json:"seed"`
	IssueCount            int    `json:"issueCount"`
	DependencyCount       int    `json:"dependencyCount"`
	LabelCount            int    `json:"labelCount"`
	CommentCount          int    `json:"commentCount"`
	GraphShape            string `json:"graphShape"`
	TextDistributionBytes []int  `json:"textDistributionBytes"`
	SchemaVersion         int    `json:"schemaVersion"`
	StorageProfile        string `json:"storageProfile"`
}

type workloadPolicy struct {
	ID         string  `json:"id"`
	Category   string  `json:"category"`
	Profile    string  `json:"profile"`
	Fixture    *string `json:"fixture"`
	CacheState string  `json:"cacheState"`
	Observer   string  `json:"observer"`
	Admission  string  `json:"admission,omitempty"`
}
