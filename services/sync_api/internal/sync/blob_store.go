package sync

import (
	"context"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type payloadBlobStore interface {
	PutPayload(changeID string, encryptedPayload string) (string, error)
	GetPayload(reference string) (string, error)
}

type S3PayloadStore struct {
	client     *s3.Client
	bucketName string
}

func NewS3PayloadStore(client *s3.Client, bucketName string) *S3PayloadStore {
	return &S3PayloadStore{
		client:     client,
		bucketName: bucketName,
	}
}

func (s *S3PayloadStore) PutPayload(changeID string, encryptedPayload string) (string, error) {
	key := "changes/" + changeID + ".payload"
	_, err := s.client.PutObject(context.Background(), &s3.PutObjectInput{
		Bucket:      &s.bucketName,
		Key:         &key,
		Body:        strings.NewReader(encryptedPayload),
		ContentType: awsString("text/plain"),
	})
	if err != nil {
		return "", err
	}

	return key, nil
}

func (s *S3PayloadStore) GetPayload(reference string) (string, error) {
	output, err := s.client.GetObject(context.Background(), &s3.GetObjectInput{
		Bucket: &s.bucketName,
		Key:    &reference,
	})
	if err != nil {
		return "", err
	}
	defer output.Body.Close()

	raw, err := io.ReadAll(output.Body)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func awsString(value string) *string {
	return &value
}
