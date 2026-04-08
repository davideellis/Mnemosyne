package sync

import (
	"errors"
	"fmt"
	stdsync "sync"
)

var (
	ErrAccountExists      = errors.New("account already exists")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidSession     = errors.New("invalid session")
	ErrChangeRejected     = errors.New("change rejected")
	ErrObjectNotInTrash   = errors.New("object not in trash")
)

type accountRecord struct {
	AccountID                     string
	Email                         string
	PasswordVerifier              string
	EncryptedMasterKeyForPassword string
	EncryptedMasterKeyForRecovery string
	RecoveryKeyHint               string
	Devices                       map[string]Device
}

type MemoryStore struct {
	mu             stdsync.Mutex
	account        *accountRecord
	sessions       map[string]string
	changes        []SyncChange
	trashObjectIDs map[string]bool
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		sessions:       map[string]string{},
		trashObjectIDs: map[string]bool{},
	}
}

func (s *MemoryStore) Bootstrap(req AccountBootstrapRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account != nil {
		return AuthSession{}, ErrAccountExists
	}

	accountID := "acct_local"
	sessionToken := "session_bootstrap"
	s.account = &accountRecord{
		AccountID:                     accountID,
		Email:                         req.Email,
		PasswordVerifier:              req.PasswordVerifier,
		EncryptedMasterKeyForPassword: req.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: req.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               req.RecoveryKeyHint,
		Devices:                       map[string]Device{req.Device.DeviceID: req.Device},
	}
	s.sessions[sessionToken] = accountID

	return AuthSession{
		SessionToken: sessionToken,
		AccountID:    accountID,
	}, nil
}

func (s *MemoryStore) Login(req LoginRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account == nil || s.account.Email != req.Email || s.account.PasswordVerifier != req.PasswordVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := fmt.Sprintf("session_%d", len(s.sessions)+1)
	s.sessions[sessionToken] = s.account.AccountID

	return AuthSession{
		SessionToken: sessionToken,
		AccountID:    s.account.AccountID,
	}, nil
}

func (s *MemoryStore) RegisterDevice(req DeviceRegistrationRequest) (Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok || s.account == nil {
		return Device{}, ErrInvalidSession
	}
	s.account.Devices[req.Device.DeviceID] = req.Device
	return req.Device, nil
}

func (s *MemoryStore) Pull(req SyncPullRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok {
		return PullResponse{}, ErrInvalidSession
	}

	start := 0
	if req.Cursor != "" {
		for index, change := range s.changes {
			if change.ChangeID == req.Cursor {
				start = index + 1
				break
			}
		}
	}

	responseChanges := make([]SyncChange, len(s.changes[start:]))
	copy(responseChanges, s.changes[start:])

	cursor := req.Cursor
	if len(s.changes) > 0 {
		cursor = s.changes[len(s.changes)-1].ChangeID
	}

	return PullResponse{
		Cursor:  cursor,
		Changes: responseChanges,
	}, nil
}

func (s *MemoryStore) Push(req SyncPushRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok {
		return PullResponse{}, ErrInvalidSession
	}

	for _, change := range req.Changes {
		if change.ChangeID == "" || change.ObjectID == "" {
			return PullResponse{}, ErrChangeRejected
		}
		if change.Operation == "trash" {
			s.trashObjectIDs[change.ObjectID] = true
		}
		if change.Operation == "restore" {
			delete(s.trashObjectIDs, change.ObjectID)
		}
		s.changes = append(s.changes, change)
	}

	cursor := req.Cursor
	if len(s.changes) > 0 {
		cursor = s.changes[len(s.changes)-1].ChangeID
	}

	return PullResponse{
		Cursor:  cursor,
		Changes: nil,
	}, nil
}

func (s *MemoryStore) RestoreTrash(req RestoreTrashRequest) (SyncChange, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok {
		return SyncChange{}, ErrInvalidSession
	}
	if !s.trashObjectIDs[req.ObjectID] {
		return SyncChange{}, ErrObjectNotInTrash
	}

	change := SyncChange{
		ChangeID:          fmt.Sprintf("restore_%d", len(s.changes)+1),
		ObjectID:          req.ObjectID,
		Kind:              "note",
		Operation:         "restore",
		LogicalTimestamp:  "",
		OriginDeviceID:    "server",
		EncryptedMetadata: "",
		EncryptedPayload:  "",
	}

	delete(s.trashObjectIDs, req.ObjectID)
	s.changes = append(s.changes, change)
	return change, nil
}
