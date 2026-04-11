package runtime

import "testing"

func TestReadBuildInfoUsesEnvironment(t *testing.T) {
	t.Setenv("MNEMOSYNE_BUILD_SHA", "abc123")
	t.Setenv("MNEMOSYNE_AWS_MODE", "lambda")

	info := ReadBuildInfo()

	if info.BuildSHA != "abc123" {
		t.Fatalf("expected build sha abc123, got %q", info.BuildSHA)
	}
	if info.AWSMode != "lambda" {
		t.Fatalf("expected aws mode lambda, got %q", info.AWSMode)
	}
}

func TestReadBuildInfoDefaultsToEmptyValues(t *testing.T) {
	t.Setenv("MNEMOSYNE_BUILD_SHA", "")
	t.Setenv("MNEMOSYNE_AWS_MODE", "")

	info := ReadBuildInfo()

	if info.BuildSHA != "" {
		t.Fatalf("expected empty build sha, got %q", info.BuildSHA)
	}
	if info.AWSMode != "" {
		t.Fatalf("expected empty aws mode, got %q", info.AWSMode)
	}
}
