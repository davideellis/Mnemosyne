package main

import (
	"log"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/awslabs/aws-lambda-go-api-proxy/httpadapter"
	"github.com/davideellis/Mnemosyne/services/sync_api/internal/api"
	"github.com/davideellis/Mnemosyne/services/sync_api/internal/runtime"
)

func main() {
	store, err := runtime.BuildStore()
	if err != nil {
		log.Fatal(err)
	}
	buildInfo := runtime.ReadBuildInfo()

	server := api.NewServer(
		store,
		api.WithBuildInfo(api.BuildInfo{
			BuildSHA: buildInfo.BuildSHA,
			AWSMode:  buildInfo.AWSMode,
		}),
	)
	adapter := httpadapter.NewV2(server.Routes())
	lambda.Start(adapter.ProxyWithContext)
}
