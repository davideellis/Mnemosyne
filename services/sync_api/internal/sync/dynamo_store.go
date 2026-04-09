package sync

import (
	"context"
	"encoding/json"
	stdsync "sync"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

const (
	dynamoStatePK        = "STATE"
	dynamoStateSK        = "STATE"
	dynamoStateAttribute = "StateJSON"
)

type DynamoStore struct {
	mu        stdsync.Mutex
	client    *dynamodb.Client
	tableName string
	state     fileStoreState
}

func NewDynamoStore(tableName string) (*DynamoStore, error) {
	cfg, err := awsconfig.LoadDefaultConfig(context.Background())
	if err != nil {
		return nil, err
	}

	store := &DynamoStore{
		client:    dynamodb.NewFromConfig(cfg),
		tableName: tableName,
		state: fileStoreState{
			Sessions:       map[string]string{},
			TrashObjectIDs: map[string]bool{},
		},
	}

	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *DynamoStore) Bootstrap(req AccountBootstrapRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account != nil {
		return AuthSession{}, ErrAccountExists
	}

	accountID := "acct_local"
	sessionToken := "session_bootstrap"
	s.state.Account = &accountRecord{
		AccountID:                     accountID,
		Email:                         req.Email,
		PasswordVerifier:              req.PasswordVerifier,
		EncryptedMasterKeyForPassword: req.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: req.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               req.RecoveryKeyHint,
		Devices:                       map[string]Device{req.Device.DeviceID: req.Device},
	}
	s.state.Sessions[sessionToken] = accountID

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}

	return AuthSession{
		SessionToken: sessionToken,
		AccountID:    accountID,
	}, nil
}

func (s *DynamoStore) Login(req LoginRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account == nil ||
		s.state.Account.Email != req.Email ||
		s.state.Account.PasswordVerifier != req.PasswordVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := sessionTokenForCount(len(s.state.Sessions) + 1)
	s.state.Sessions[sessionToken] = s.state.Account.AccountID

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}

	return AuthSession{
		SessionToken: sessionToken,
		AccountID:    s.state.Account.AccountID,
	}, nil
}

func (s *DynamoStore) RegisterDevice(req DeviceRegistrationRequest) (Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.state.Sessions[req.SessionToken]; !ok || s.state.Account == nil {
		return Device{}, ErrInvalidSession
	}
	s.state.Account.Devices[req.Device.DeviceID] = req.Device

	if err := s.save(); err != nil {
		return Device{}, err
	}

	return req.Device, nil
}

func (s *DynamoStore) Pull(req SyncPullRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.state.Sessions[req.SessionToken]; !ok {
		return PullResponse{}, ErrInvalidSession
	}

	start := 0
	if req.Cursor != "" {
		for index, change := range s.state.Changes {
			if change.ChangeID == req.Cursor {
				start = index + 1
				break
			}
		}
	}

	responseChanges := make([]SyncChange, len(s.state.Changes[start:]))
	copy(responseChanges, s.state.Changes[start:])

	cursor := req.Cursor
	if len(s.state.Changes) > 0 {
		cursor = s.state.Changes[len(s.state.Changes)-1].ChangeID
	}

	return PullResponse{
		Cursor:  cursor,
		Changes: responseChanges,
	}, nil
}

func (s *DynamoStore) Push(req SyncPushRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.state.Sessions[req.SessionToken]; !ok {
		return PullResponse{}, ErrInvalidSession
	}

	for _, change := range req.Changes {
		if change.ChangeID == "" || change.ObjectID == "" {
			return PullResponse{}, ErrChangeRejected
		}
		if change.Operation == "trash" {
			s.state.TrashObjectIDs[change.ObjectID] = true
		}
		if change.Operation == "restore" {
			delete(s.state.TrashObjectIDs, change.ObjectID)
		}
		s.state.Changes = append(s.state.Changes, change)
	}

	if err := s.save(); err != nil {
		return PullResponse{}, err
	}

	cursor := req.Cursor
	if len(s.state.Changes) > 0 {
		cursor = s.state.Changes[len(s.state.Changes)-1].ChangeID
	}

	return PullResponse{
		Cursor:  cursor,
		Changes: nil,
	}, nil
}

func (s *DynamoStore) RestoreTrash(req RestoreTrashRequest) (SyncChange, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.state.Sessions[req.SessionToken]; !ok {
		return SyncChange{}, ErrInvalidSession
	}
	if !s.state.TrashObjectIDs[req.ObjectID] {
		return SyncChange{}, ErrObjectNotInTrash
	}

	change := SyncChange{
		ChangeID:          restoreChangeID(len(s.state.Changes) + 1),
		ObjectID:          req.ObjectID,
		Kind:              "note",
		Operation:         "restore",
		LogicalTimestamp:  "",
		OriginDeviceID:    "server",
		EncryptedMetadata: "",
		EncryptedPayload:  "",
	}

	delete(s.state.TrashObjectIDs, req.ObjectID)
	s.state.Changes = append(s.state.Changes, change)

	if err := s.save(); err != nil {
		return SyncChange{}, err
	}

	return change, nil
}

func (s *DynamoStore) load() error {
	output, err := s.client.GetItem(context.Background(), &dynamodb.GetItemInput{
		TableName: &s.tableName,
		Key: map[string]types.AttributeValue{
			"PK": &types.AttributeValueMemberS{Value: dynamoStatePK},
			"SK": &types.AttributeValueMemberS{Value: dynamoStateSK},
		},
		ConsistentRead: awsBool(true),
	})
	if err != nil {
		return err
	}

	if len(output.Item) == 0 {
		return nil
	}

	stateJSON, ok := output.Item[dynamoStateAttribute].(*types.AttributeValueMemberS)
	if !ok || stateJSON.Value == "" {
		return nil
	}

	var state fileStoreState
	if err := json.Unmarshal([]byte(stateJSON.Value), &state); err != nil {
		return err
	}
	if state.Sessions == nil {
		state.Sessions = map[string]string{}
	}
	if state.TrashObjectIDs == nil {
		state.TrashObjectIDs = map[string]bool{}
	}
	s.state = state
	return nil
}

func (s *DynamoStore) save() error {
	raw, err := json.Marshal(s.state)
	if err != nil {
		return err
	}

	_, err = s.client.PutItem(context.Background(), &dynamodb.PutItemInput{
		TableName: &s.tableName,
		Item: map[string]types.AttributeValue{
			"PK":        &types.AttributeValueMemberS{Value: dynamoStatePK},
			"SK":        &types.AttributeValueMemberS{Value: dynamoStateSK},
			"StateJSON": &types.AttributeValueMemberS{Value: string(raw)},
			"UpdatedAt": &types.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339)},
		},
	})
	return err
}

func awsBool(value bool) *bool {
	return &value
}
