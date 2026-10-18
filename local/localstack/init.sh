#!/bin/bash
# LocalStack ready hook: the same buckets, queues, keys and notification as infra/, with
# local names. Idempotent.
set -euo pipefail
export AWS_DEFAULT_REGION=eu-west-1

awslocal kms create-alias --alias-name alias/docbridge-local-jwt \
  --target-key-id "$(awslocal kms create-key --key-usage SIGN_VERIFY --key-spec ECC_NIST_P256 --query KeyMetadata.KeyId --output text)" 2>/dev/null || true
awslocal kms create-alias --alias-name alias/docbridge-local-staging \
  --target-key-id "$(awslocal kms create-key --query KeyMetadata.KeyId --output text)" 2>/dev/null || true

awslocal sqs create-queue --queue-name docbridge-local-upload-events >/dev/null
awslocal sqs create-queue --queue-name docbridge-local-tasks-dlq >/dev/null
dlq_arn="$(awslocal sqs get-queue-attributes --queue-url http://sqs.eu-west-1.localhost.localstack.cloud:4566/000000000000/docbridge-local-tasks-dlq \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)"
awslocal sqs create-queue --queue-name docbridge-local-tasks \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$dlq_arn\\\",\\\"maxReceiveCount\\\":\\\"5\\\"}\",\"VisibilityTimeout\":\"360\"}" >/dev/null

for b in docbridge-local-staging docbridge-local-documents; do
  awslocal s3api create-bucket --bucket "$b" --create-bucket-configuration LocationConstraint=eu-west-1 >/dev/null 2>&1 || true
done
awslocal s3api put-bucket-cors --bucket docbridge-local-staging --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["http://localhost:5173"],
    "AllowedMethods": ["POST", "PUT"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag", "x-amz-checksum-sha256"],
    "MaxAgeSeconds": 3600
  }]
}'
awslocal s3api put-bucket-notification-configuration --bucket docbridge-local-staging --notification-configuration '{
  "QueueConfigurations": [{
    "QueueArn": "arn:aws:sqs:eu-west-1:000000000000:docbridge-local-upload-events",
    "Events": ["s3:ObjectCreated:*"],
    "Filter": {"Key": {"FilterRules": [{"Name": "prefix", "Value": "staging/"}]}}
  }]
}'
echo "localstack: docbridge resources ready"
