package sync

import (
	"errors"
	"fmt"
	stdsync "sync"
	"time"
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
	RecoveryVerifier              string
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
	latestChanges  map[string]SyncChange
	trashObjectIDs map[string]bool
}

func sessionTokenForCount(count int) string {
	return fmt.Sprintf("session_%d", count)
}

func restoreChangeID(count int) string {
	return fmt.Sprintf("restore_%d", count)
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		sessions:       map[string]string{},
		latestChanges:  map[string]SyncChange{},
		trashObjectIDs: map[string]bool{},
	}
}

func authSessionForAccount(sessionToken string, account *accountRecord) AuthSession {
	return AuthSession{
		SessionToken:                  sessionToken,
		AccountID:                     account.AccountID,
		EncryptedMasterKeyForPassword: account.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: account.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               account.RecoveryKeyHint,
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
		RecoveryVerifier:              req.RecoveryVerifier,
		EncryptedMasterKeyForPassword: req.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: req.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               req.RecoveryKeyHint,
		Devices:                       map[string]Device{req.Device.DeviceID: req.Device},
	}
	s.sessions[sessionToken] = accountID

	return authSessionForAccount(sessionToken, s.account), nil
}

func (s *MemoryStore) Recover(req RecoveryRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account == nil ||
		s.account.Email != req.Email ||
		s.account.RecoveryVerifier != req.RecoveryVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := sessionTokenForCount(len(s.sessions) + 1)
	s.sessions[sessionToken] = s.account.AccountID

	return authSessionForAccount(sessionToken, s.account), nil
}

func (s *MemoryStore) Login(req LoginRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account == nil || s.account.Email != req.Email || s.account.PasswordVerifier != req.PasswordVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := sessionTokenForCount(len(s.sessions) + 1)
	s.sessions[sessionToken] = s.account.AccountID

	return authSessionForAccount(sessionToken, s.account), nil
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
		if !shouldAcceptChange(s.latestChanges[change.ObjectID], change) {
			continue
		}
		if change.Operation == "trash" {
			s.trashObjectIDs[change.ObjectID] = true
		}
		if change.Operation == "restore" {
			delete(s.trashObjectIDs, change.ObjectID)
		}
		s.latestChanges[change.ObjectID] = change
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
		ChangeID:          restoreChangeID(len(s.changes) + 1),
		ObjectID:          req.ObjectID,
		Kind:              "note",
		Operation:         "restore",
		LogicalTimestamp:  "",
		OriginDeviceID:    "server",
		EncryptedMetadata: "",
		EncryptedPayload:  "",
	}

	delete(s.trashObjectIDs, req.ObjectID)
	s.latestChanges[req.ObjectID] = change
	s.changes = append(s.changes, change)
	return change, nil
}

func shouldAcceptChange(current SyncChange, incoming SyncChange) bool {
	if current.ChangeID == "" {
		return true
	}

	currentTimestamp := parseLogicalTimestamp(current.LogicalTimestamp)
	incomingTimestamp := parseLogicalTimestamp(incoming.LogicalTimestamp)

	switch {
	case incomingTimestamp.After(currentTimestamp):
		return true
	case incomingTimestamp.Before(currentTimestamp):
		return false
	default:
		return incoming.ChangeID > current.ChangeID
	}
}

func parseLogicalTimestamp(value string) time.Time {
	if value == "" {
		return time.Time{}
	}

	parsed, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return time.Time{}
	}
	return parsed.UTC()
}
