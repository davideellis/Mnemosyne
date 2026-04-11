package sync

import (
	"encoding/json"
	"os"
	"path/filepath"
	stdsync "sync"
	"time"
)

type fileStoreState struct {
	Account          *accountRecord            `json:"account"`
	Sessions         map[string]string         `json:"sessions"`
	SessionIssuedAt  map[string]string         `json:"sessionIssuedAt"`
	SessionDeviceIDs map[string]string         `json:"sessionDeviceIds"`
	Changes          []SyncChange              `json:"changes"`
	LatestChanges    map[string]SyncChange     `json:"latestChanges"`
	PendingApprovals map[string]DeviceApproval `json:"pendingApprovals"`
	PayloadRefs      map[string]string         `json:"payloadRefs"`
	TrashObjectIDs   map[string]bool           `json:"trashObjectIds"`
}

type FileStore struct {
	mu       stdsync.Mutex
	filePath string
	state    fileStoreState
}

func newFileStoreState() fileStoreState {
	return fileStoreState{
		Sessions:         map[string]string{},
		SessionIssuedAt:  map[string]string{},
		SessionDeviceIDs: map[string]string{},
		LatestChanges:    map[string]SyncChange{},
		PendingApprovals: map[string]DeviceApproval{},
		PayloadRefs:      map[string]string{},
		TrashObjectIDs:   map[string]bool{},
	}
}

func normalizeFileStoreState(state fileStoreState) fileStoreState {
	if state.Sessions == nil {
		state.Sessions = map[string]string{}
	}
	if state.SessionIssuedAt == nil {
		state.SessionIssuedAt = map[string]string{}
	}
	if state.SessionDeviceIDs == nil {
		state.SessionDeviceIDs = map[string]string{}
	}
	if state.LatestChanges == nil {
		state.LatestChanges = map[string]SyncChange{}
	}
	if state.PendingApprovals == nil {
		state.PendingApprovals = map[string]DeviceApproval{}
	}
	if state.PayloadRefs == nil {
		state.PayloadRefs = map[string]string{}
	}
	if state.TrashObjectIDs == nil {
		state.TrashObjectIDs = map[string]bool{}
	}
	pruneExpiredSessions(
		state.Sessions,
		state.SessionIssuedAt,
		state.SessionDeviceIDs,
		time.Now().UTC(),
	)
	pruneExpiredApprovals(state.PendingApprovals, time.Now().UTC())
	return state
}

func NewFileStore(filePath string) (*FileStore, error) {
	store := &FileStore{
		filePath: filePath,
		state:    newFileStoreState(),
	}

	if err := store.load(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *FileStore) Bootstrap(req AccountBootstrapRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account != nil {
		return AuthSession{}, ErrAccountExists
	}

	accountID := "acct_local"
	sessionToken := "session_bootstrap"
	issuedAt := currentTimestamp()
	device := touchDevice(req.Device, issuedAt)
	s.state.Account = &accountRecord{
		AccountID:                     accountID,
		Email:                         req.Email,
		PasswordVerifier:              req.PasswordVerifier,
		RecoveryVerifier:              req.RecoveryVerifier,
		EncryptedMasterKeyForPassword: req.EncryptedMasterKeyForPassword,
		EncryptedMasterKeyForRecovery: req.EncryptedMasterKeyForRecovery,
		RecoveryKeyHint:               req.RecoveryKeyHint,
		Devices:                       map[string]Device{device.DeviceID: device},
	}
	putSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		sessionToken,
		accountID,
		issuedAt,
		req.Device.DeviceID,
	)

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}

	return authSessionForAccount(sessionToken, s.state.Account, issuedAt), nil
}

func (s *FileStore) Recover(req RecoveryRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account == nil ||
		s.state.Account.Email != req.Email ||
		s.state.Account.RecoveryVerifier != req.RecoveryVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := sessionTokenForCount(len(s.state.Sessions) + 1)
	issuedAt := currentTimestamp()
	putSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		sessionToken,
		s.state.Account.AccountID,
		issuedAt,
		req.Device.DeviceID,
	)
	if req.Device.DeviceID != "" {
		device := touchDevice(req.Device, issuedAt)
		s.state.Account.Devices[device.DeviceID] = device
	}

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}

	return authSessionForAccount(sessionToken, s.state.Account, issuedAt), nil
}

func (s *FileStore) Login(req LoginRequest) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account == nil ||
		s.state.Account.Email != req.Email ||
		s.state.Account.PasswordVerifier != req.PasswordVerifier {
		return AuthSession{}, ErrInvalidCredentials
	}

	sessionToken := sessionTokenForCount(len(s.state.Sessions) + 1)
	issuedAt := currentTimestamp()
	putSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		sessionToken,
		s.state.Account.AccountID,
		issuedAt,
		req.Device.DeviceID,
	)
	if req.Device.DeviceID != "" {
		device := touchDevice(req.Device, issuedAt)
		s.state.Account.Devices[device.DeviceID] = device
	}

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}

	return authSessionForAccount(sessionToken, s.state.Account, issuedAt), nil
}

func (s *FileStore) Logout(req LogoutRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok {
		return ErrInvalidSession
	}
	removeSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
	)
	return s.save()
}

func (s *FileStore) RegisterDevice(req DeviceRegistrationRequest) (Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok || s.state.Account == nil {
		return Device{}, ErrInvalidSession
	}
	device := touchDevice(req.Device, currentTimestamp())
	s.state.Account.Devices[device.DeviceID] = device

	if err := s.save(); err != nil {
		return Device{}, err
	}

	return device, nil
}

func (s *FileStore) ListDevices(req DeviceListRequest) ([]Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok || s.state.Account == nil {
		return nil, ErrInvalidSession
	}

	return sortedDevices(s.state.Account.Devices), nil
}

func (s *FileStore) RevokeDevice(req DeviceRevokeRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok || s.state.Account == nil {
		return ErrInvalidSession
	}
	if req.DeviceID == "" {
		return ErrInvalidDevice
	}

	delete(s.state.Account.Devices, req.DeviceID)
	revokeDeviceSessions(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.DeviceID,
	)
	return s.save()
}

func (s *FileStore) StartDeviceApproval(
	req DeviceApprovalStartRequest,
) (DeviceApproval, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok || s.state.Account == nil {
		return DeviceApproval{}, ErrInvalidSession
	}

	approval := DeviceApproval{
		AccountID:        s.state.Account.AccountID,
		Email:            s.state.Account.Email,
		ApprovalVerifier: req.ApprovalVerifier,
		WrappedKeyBlob:   req.WrappedKeyBlob,
		ExpiresAt:        time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339),
	}
	s.state.PendingApprovals[req.ApprovalVerifier] = approval

	if err := s.save(); err != nil {
		return DeviceApproval{}, err
	}
	return approval, nil
}

func (s *FileStore) ConsumeDeviceApproval(
	req DeviceApprovalConsumeRequest,
) (AuthSession, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.state.Account == nil || s.state.Account.Email != req.Email {
		return AuthSession{}, ErrInvalidApproval
	}

	approval, ok := s.state.PendingApprovals[req.ApprovalVerifier]
	if !ok || approval.Email != req.Email || approval.WrappedKeyBlob == "" {
		return AuthSession{}, ErrInvalidApproval
	}
	if parseLogicalTimestamp(approval.ExpiresAt).Before(time.Now().UTC()) {
		delete(s.state.PendingApprovals, req.ApprovalVerifier)
		_ = s.save()
		return AuthSession{}, ErrInvalidApproval
	}

	issuedAt := currentTimestamp()
	device := touchDevice(req.Device, issuedAt)
	s.state.Account.Devices[device.DeviceID] = device
	sessionToken := sessionTokenForCount(len(s.state.Sessions) + 1)
	putSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		sessionToken,
		s.state.Account.AccountID,
		issuedAt,
		req.Device.DeviceID,
	)
	delete(s.state.PendingApprovals, req.ApprovalVerifier)

	if err := s.save(); err != nil {
		return AuthSession{}, err
	}
	return authSessionForApproval(
		sessionToken,
		s.state.Account,
		issuedAt,
		approval.WrappedKeyBlob,
	), nil
}

func (s *FileStore) Pull(req SyncPullRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok {
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

func (s *FileStore) Push(req SyncPushRequest) (PullResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok {
		return PullResponse{}, ErrInvalidSession
	}

	seenAt := currentTimestamp()
	for _, change := range req.Changes {
		if change.ChangeID == "" || change.ObjectID == "" {
			return PullResponse{}, ErrChangeRejected
		}
		touchExistingDevice(s.state.Account, change.OriginDeviceID, seenAt)
		if !shouldAcceptChange(s.state.LatestChanges[change.ObjectID], change) {
			continue
		}
		if change.Operation == "trash" {
			s.state.TrashObjectIDs[change.ObjectID] = true
		}
		if change.Operation == "restore" {
			delete(s.state.TrashObjectIDs, change.ObjectID)
		}
		s.state.LatestChanges[change.ObjectID] = change
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

func (s *FileStore) RestoreTrash(req RestoreTrashRequest) (SyncChange, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := validateSession(
		s.state.Sessions,
		s.state.SessionIssuedAt,
		s.state.SessionDeviceIDs,
		req.SessionToken,
		time.Now().UTC(),
	); !ok {
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
	s.state.LatestChanges[req.ObjectID] = change
	s.state.Changes = append(s.state.Changes, change)

	if err := s.save(); err != nil {
		return SyncChange{}, err
	}

	return change, nil
}

func (s *FileStore) load() error {
	raw, err := os.ReadFile(s.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			s.state = newFileStoreState()
			return nil
		}
		return err
	}

	var state fileStoreState
	if err := json.Unmarshal(raw, &state); err != nil {
		return err
	}
	s.state = normalizeFileStoreState(state)
	return nil
}

func (s *FileStore) save() error {
	if err := os.MkdirAll(filepath.Dir(s.filePath), 0o755); err != nil {
		return err
	}

	raw, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.filePath, raw, 0o600)
}
