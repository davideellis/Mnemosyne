package runtime

import "os"

type BuildInfo struct {
	BuildSHA string `json:"buildSha,omitempty"`
	AWSMode  string `json:"awsMode,omitempty"`
}

func ReadBuildInfo() BuildInfo {
	return BuildInfo{
		BuildSHA: os.Getenv("MNEMOSYNE_BUILD_SHA"),
		AWSMode:  os.Getenv("MNEMOSYNE_AWS_MODE"),
	}
}
