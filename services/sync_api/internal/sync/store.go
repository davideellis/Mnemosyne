package sync

import (
	"errors"
	"fmt"
	"sort"
	stdsync "sync"
	"time"
)

var (
	ErrAccountExists      = errors.New("account already exists")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidSession     = errors.New("invalid session")
	ErrChangeRejected     = errors.New("change rejected")
	ErrObjectNotInTrash   = errors.New("object not in trash")
	ErrInvalidApproval    = errors.New("invalid approval")
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
	mu               stdsync.Mutex
	account          *accountRecord
	sessions         map[string]string
	changes          []SyncChange
	latestChanges    map[string]SyncChange
	pendingApprovals map[string]DeviceApproval
	trashObjectIDs   map[string]bool
}

func sessionTokenForCount(count int) string {
	return fmt.Sprintf("session_%d", count)
}

func restoreChangeID(count int) string {
	return fmt.Sprintf("restore_%d", count)
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		sessions:         map[string]string{},
		latestChanges:    map[string]SyncChange{},
		pendingApprovals: map[string]DeviceApproval{},
		trashObjectIDs:   map[string]bool{},
	}
}

func currentTimestamp() string {
	return time.Now().UTC().Format(time.RFC3339)
}

func touchDevice(device Device, seenAt string) Device {
	device.LastSeenAt = seenAt
	return device
}

func touchExistingDevice(account *accountRecord, deviceID string, seenAt string) {
	if account == nil || account.Devices == nil || deviceID == "" {
		return
	}

	device, ok := account.Devices[deviceID]
	if !ok {
		return
	}
	device.LastSeenAt = seenAt
	account.Devices[deviceID] = device
}

func sortedDevices(devicesByID map[string]Device) []Device {
	devices := make([]Device, 0, len(devicesByID))
	for _, device := range devicesByID {
		devices = append(devices, device)
	}

	sort.Slice(devices, func(left, right int) bool {
		if devices[left].LastSeenAt != devices[right].LastSeenAt {
			return devices[left].LastSeenAt > devices[right].LastSeenAt
		}
		if devices[left].DeviceName != devices[right].DeviceName {
			return devices[left].DeviceName < devices[right].DeviceName
		}
		return devices[left].DeviceID < devices[right].DeviceID
	})
	return devices
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

func authSessionForApproval(
	sessionToken string,
	account *accountRecord,
	wrappedKeyBlob string,
) AuthSession {
	session := authSessionForAccount(sessionToken, account)
	session.WrappedMasterKeyForApproval = wrappedKeyBlob
	return session
}

func (s *MemoryStore) Bootstrap(req AccountBootstrapRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account != nil {
		return AuthSession{}, ErrAccountExists
	}

	accountID := "acct_local"
	sessionToken := "session_bootstrap"
	device := touchDevice(req.Device, currentTimestamp())
	s.account = &accountRecord{
		AccountID:                     accountID,
		Email:                         req.Email,
		PasswordVerifier:              req.PasswordVerifier,
		RecoveryVerifier:              req.RecoveryVerifier,
		EncryptedMasterKeyForPassword: req.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: req.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               req.RecoveryKeyHint,
		Devices:                       map[string]Device{device.DeviceID: device},
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
	if req.Device.DeviceID != "" {
		device := touchDevice(req.Device, currentTimestamp())
		s.account.Devices[device.DeviceID] = device
	}

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
	if req.Device.DeviceID != "" {
		device := touchDevice(req.Device, currentTimestamp())
		s.account.Devices[device.DeviceID] = device
	}

	return authSessionForAccount(sessionToken, s.account), nil
}

func (s *MemoryStore) Logout(req LogoutRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok {
		return ErrInvalidSession
	}
	delete(s.sessions, req.SessionToken)
	return nil
}

func (s *MemoryStore) RegisterDevice(req DeviceRegistrationRequest) (Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok || s.account == nil {
		return Device{}, ErrInvalidSession
	}
	device := touchDevice(req.Device, currentTimestamp())
	s.account.Devices[device.DeviceID] = device
	return device, nil
}

func (s *MemoryStore) ListDevices(req DeviceListRequest) ([]Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.sessions[req.SessionToken]; !ok || s.account == nil {
		return nil, ErrInvalidSession
	}

	return sortedDevices(s.account.Devices), nil
}

func (s *MemoryStore) StartDeviceApproval(
	req DeviceApprovalStartRequest,
) (DeviceApproval, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	accountID, ok := s.sessions[req.SessionToken]
	if !ok || s.account == nil || s.account.AccountID != accountID {
		return DeviceApproval{}, ErrInvalidSession
	}

	approval := DeviceApproval{
		AccountID:        s.account.AccountID,
		Email:            s.account.Email,
		ApprovalVerifier: req.ApprovalVerifier,
		WrappedKeyBlob:   req.WrappedKeyBlob,
		ExpiresAt:        time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
	}
	s.pendingApprovals[req.ApprovalVerifier] = approval
	return approval, nil
}

func (s *MemoryStore) ConsumeDeviceApproval(
	req DeviceApprovalConsumeRequest,
) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.account == nil || s.account.Email != req.Email {
		return AuthSession{}, ErrInvalidApproval
	}

	approval, ok := s.pendingApprovals[req.ApprovalVerifier]
	if !ok || approval.Email != req.Email || approval.WrappedKeyBlob == "" {
		return AuthSession{}, ErrInvalidApproval
	}
	if parseLogicalTimestamp(approval.ExpiresAt).Before(time.Now().UTC()) {
		delete(s.pendingApprovals, req.ApprovalVerifier)
		return AuthSession{}, ErrInvalidApproval
	}

	device := touchDevice(req.Device, currentTimestamp())
	s.account.Devices[device.DeviceID] = device
	sessionToken := sessionTokenForCount(len(s.sessions) + 1)
	s.sessions[sessionToken] = s.account.AccountID
	delete(s.pendingApprovals, req.ApprovalVerifier)
	return authSessionForApproval(sessionToken, s.account, approval.WrappedKeyBlob), nil
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

	seenAt := currentTimestamp()
	for _, change := range req.Changes {
		if change.ChangeID == "" || change.ObjectID == "" {
			return PullResponse{}, ErrChangeRejected
		}
		touchExistingDevice(s.account, change.OriginDeviceID, seenAt)
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
