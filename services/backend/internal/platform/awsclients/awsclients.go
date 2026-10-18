// Package awsclients builds AWS SDK clients. Locally, AWS_ENDPOINT_URL points every client
// at LocalStack; the SDK reads it on its own, so nothing here is LocalStack-specific except
// path-style S3 addressing.
package awsclients

import (
	"context"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

// Clients holds the clients the services use.
type Clients struct {
	Config aws.Config
	S3     *s3.Client
	SQS    *sqs.Client
	KMS    *kms.Client
}

// New loads the default credential chain and builds the clients.
func New(ctx context.Context) (*Clients, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	pathStyle := os.Getenv("AWS_ENDPOINT_URL") != ""
	return &Clients{
		Config: cfg,
		S3:     s3.NewFromConfig(cfg, func(o *s3.Options) { o.UsePathStyle = pathStyle }),
		SQS:    sqs.NewFromConfig(cfg),
		KMS:    kms.NewFromConfig(cfg),
	}, nil
}
