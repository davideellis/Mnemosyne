package sync

import "testing"

func TestMemoryStoreRejectsStaleChanges(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	_, err = store.Push(SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []SyncChange{
			{
				ChangeID:         "change-2",
				ObjectID:         "note-1",
				Kind:             "note",
				Operation:        "upsert",
				LogicalTimestamp: "2026-04-08T18:00:00Z",
			},
			{
				ChangeID:         "change-1",
				ObjectID:         "note-1",
				Kind:             "note",
				Operation:        "upsert",
				LogicalTimestamp: "2026-04-08T17:59:00Z",
			},
		},
	})
	if err != nil {
		t.Fatalf("push: %v", err)
	}

	pull, err := store.Pull(SyncPullRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(pull.Changes) != 1 {
		t.Fatalf("expected only 1 accepted change, got %d", len(pull.Changes))
	}
	if pull.Changes[0].ChangeID != "change-2" {
		t.Fatalf("expected latest change to win, got %s", pull.Changes[0].ChangeID)
	}
}

func TestShouldAcceptChangeUsesChangeIDAsTieBreaker(t *testing.T) {
	current := SyncChange{
		ChangeID:         "change-1",
		ObjectID:         "note-1",
		LogicalTimestamp: "2026-04-08T18:00:00Z",
	}

	incoming := SyncChange{
		ChangeID:         "change-2",
		ObjectID:         "note-1",
		LogicalTimestamp: "2026-04-08T18:00:00Z",
	}

	if !shouldAcceptChange(current, incoming) {
		t.Fatal("expected lexically newer change ID to win timestamp tie")
	}
	if shouldAcceptChange(incoming, current) {
		t.Fatal("expected lexically older change ID to lose timestamp tie")
	}
}

func TestMemoryStoreRecoversWithRecoveryVerifier(t *testing.T) {
	store := NewMemoryStore()

	_, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	session, err := store.Recover(RecoveryRequest{
		Email:            "user@example.com",
		RecoveryVerifier: "rec-proof",
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	if session.SessionToken == "" {
		t.Fatal("expected recovery to return a session token")
	}
	devices, err := store.ListDevices(DeviceListRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("list devices after recovery: %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("expected recovery device to be tracked, got %d devices", len(devices))
	}
}

func TestMemoryStoreConsumesDeviceApproval(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	approval, err := store.StartDeviceApproval(DeviceApprovalStartRequest{
		SessionToken:     session.SessionToken,
		ApprovalVerifier: "approval-proof",
		WrappedKeyBlob:   "wrapped-approval-key",
	})
	if err != nil {
		t.Fatalf("start approval: %v", err)
	}
	if approval.WrappedKeyBlob != "wrapped-approval-key" {
		t.Fatalf("expected wrapped key blob to persist, got %q", approval.WrappedKeyBlob)
	}

	approvedSession, err := store.ConsumeDeviceApproval(DeviceApprovalConsumeRequest{
		Email:            "user@example.com",
		ApprovalVerifier: "approval-proof",
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	if err != nil {
		t.Fatalf("consume approval: %v", err)
	}
	if approvedSession.WrappedMasterKeyForApproval != "wrapped-approval-key" {
		t.Fatalf("expected wrapped approval key in session, got %q", approvedSession.WrappedMasterKeyForApproval)
	}
}

func TestMemoryStoreLogoutInvalidatesSession(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	if err := store.Logout(LogoutRequest{SessionToken: session.SessionToken}); err != nil {
		t.Fatalf("logout: %v", err)
	}

	_, err = store.Pull(SyncPullRequest{SessionToken: session.SessionToken})
	if err == nil {
		t.Fatal("expected logged-out session to be rejected")
	}
}

func TestMemoryStoreTracksDeviceLastSeenDuringSync(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	devices, err := store.ListDevices(DeviceListRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("list devices before sync: %v", err)
	}
	if len(devices) != 1 || devices[0].LastSeenAt == "" {
		t.Fatal("expected bootstrap device to have a last-seen timestamp")
	}
	initialLastSeenAt := devices[0].LastSeenAt

	_, err = store.Push(SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []SyncChange{
			{
				ChangeID:         "change-1",
				ObjectID:         "note-1",
				Kind:             "note",
				Operation:        "upsert",
				LogicalTimestamp: "2026-04-08T18:00:00Z",
				OriginDeviceID:   "device-1",
			},
		},
	})
	if err != nil {
		t.Fatalf("push: %v", err)
	}

	devices, err = store.ListDevices(DeviceListRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("list devices after sync: %v", err)
	}
	if devices[0].LastSeenAt < initialLastSeenAt {
		t.Fatalf("expected last seen timestamp to advance, got %q then %q", initialLastSeenAt, devices[0].LastSeenAt)
	}
}

func TestMemoryStoreRejectsExpiredSessions(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	store.sessionIssuedAt[session.SessionToken] = "2026-01-01T00:00:00Z"

	_, err = store.Pull(SyncPullRequest{SessionToken: session.SessionToken})
	if err == nil {
		t.Fatal("expected expired session to be rejected")
	}
	if _, ok := store.sessions[session.SessionToken]; ok {
		t.Fatal("expected expired session to be pruned")
	}
}

func TestMemoryStoreRevokesDeviceSessions(t *testing.T) {
	store := NewMemoryStore()

	bootstrapSession, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	recoverySession, err := store.Recover(RecoveryRequest{
		Email:            "user@example.com",
		RecoveryVerifier: "rec-proof",
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}

	if err := store.RevokeDevice(DeviceRevokeRequest{
		SessionToken: bootstrapSession.SessionToken,
		DeviceID:     "device-2",
	}); err != nil {
		t.Fatalf("revoke device: %v", err)
	}

	devices, err := store.ListDevices(DeviceListRequest{SessionToken: bootstrapSession.SessionToken})
	if err != nil {
		t.Fatalf("list devices after revoke: %v", err)
	}
	if len(devices) != 1 || devices[0].DeviceID != "device-1" {
		t.Fatalf("expected only device-1 to remain, got %+v", devices)
	}

	if _, err := store.Pull(SyncPullRequest{SessionToken: recoverySession.SessionToken}); err == nil {
		t.Fatal("expected revoked device session to be rejected")
	}
}

func TestMemoryStoreLoginTracksDevice(t *testing.T) {
	store := NewMemoryStore()

	_, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	session, err := store.Login(LoginRequest{
		Email:            "user@example.com",
		PasswordVerifier: "pw-proof",
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Android Phone",
			Platform:   "android",
		},
	})
	if err != nil {
		t.Fatalf("login: %v", err)
	}

	devices, err := store.ListDevices(DeviceListRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("expected 2 devices after login, got %d", len(devices))
	}
}

func TestMemoryStoreRegisterDeviceAddsDevice(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	device, err := store.RegisterDevice(DeviceRegistrationRequest{
		SessionToken: session.SessionToken,
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	if device.DeviceID != "device-2" {
		t.Fatalf("expected device-2, got %q", device.DeviceID)
	}

	devices, err := store.ListDevices(DeviceListRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("expected 2 devices after registration, got %d", len(devices))
	}
}

func TestMemoryStoreRestoreTrashCreatesRestoreChange(t *testing.T) {
	store := NewMemoryStore()

	session, err := store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap: %v", err)
	}

	_, err = store.Push(SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []SyncChange{
			{
				ChangeID:          "change-trash-1",
				ObjectID:          "note-1",
				Kind:              "note",
				Operation:         "trash",
				LogicalTimestamp:  "2026-04-08T18:00:00Z",
				EncryptedMetadata: "meta",
				EncryptedPayload:  "payload",
			},
		},
	})
	if err != nil {
		t.Fatalf("push trash change: %v", err)
	}

	change, err := store.RestoreTrash(RestoreTrashRequest{
		SessionToken: session.SessionToken,
		ObjectID:     "note-1",
	})
	if err != nil {
		t.Fatalf("restore trash: %v", err)
	}
	if change.Operation != "restore" {
		t.Fatalf("expected restore operation, got %q", change.Operation)
	}
	if change.EncryptedMetadata == "" || change.EncryptedPayload == "" {
		t.Fatal("expected restore change to preserve encrypted note envelope")
	}

	pull, err := store.Pull(SyncPullRequest{SessionToken: session.SessionToken})
	if err != nil {
		t.Fatalf("pull: %v", err)
	}
	if len(pull.Changes) != 2 {
		t.Fatalf("expected trash + restore changes, got %d", len(pull.Changes))
	}
}
