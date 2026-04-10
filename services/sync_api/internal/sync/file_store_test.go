package sync

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFileStorePersistsBootstrapAndChanges(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

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
				ChangeID:          "change-1",
				ObjectID:          "note-1",
				Kind:              "note",
				Operation:         "upsert",
				LogicalTimestamp:  "2026-04-08T18:00:00Z",
				OriginDeviceID:    "device-1",
				EncryptedMetadata: "meta",
				EncryptedPayload:  "payload",
			},
		},
	})
	if err != nil {
		t.Fatalf("push: %v", err)
	}

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	pull, err := reloadedStore.Pull(SyncPullRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(pull.Changes) != 1 {
		t.Fatalf("expected 1 change, got %d", len(pull.Changes))
	}
	if pull.Changes[0].ObjectID != "note-1" {
		t.Fatalf("expected note-1, got %s", pull.Changes[0].ObjectID)
	}
}

func TestFileStoreRejectsStaleChangesAcrossReload(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

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
		},
	})
	if err != nil {
		t.Fatalf("push latest: %v", err)
	}

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	_, err = reloadedStore.Push(SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []SyncChange{
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
		t.Fatalf("push stale: %v", err)
	}

	pull, err := reloadedStore.Pull(SyncPullRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("pull: %v", err)
	}

	if len(pull.Changes) != 1 {
		t.Fatalf("expected only 1 accepted change, got %d", len(pull.Changes))
	}
	if pull.Changes[0].ChangeID != "change-2" {
		t.Fatalf("expected latest change to survive reload, got %s", pull.Changes[0].ChangeID)
	}
}

func TestFileStorePersistsRecoveryVerifier(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

	_, err = store.Bootstrap(AccountBootstrapRequest{
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

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	session, err := reloadedStore.Recover(RecoveryRequest{
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
	devices, err := reloadedStore.ListDevices(DeviceListRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("list devices after recovery: %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("expected recovery device to persist, got %d devices", len(devices))
	}
}

func TestFileStoreLoadClearsStateWhenBackingFileIsRemoved(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

	_, err = store.Bootstrap(AccountBootstrapRequest{
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

	if err := os.Remove(filePath); err != nil {
		t.Fatalf("remove state file: %v", err)
	}
	if err := store.load(); err != nil {
		t.Fatalf("reload after removing state file: %v", err)
	}
	if store.state.Account != nil {
		t.Fatal("expected in-memory account state to clear when backing file is missing")
	}

	_, err = store.Bootstrap(AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof-2",
		RecoveryVerifier:              "rec-proof-2",
		EncryptedMasterKeyForPassword: "enc-pw-2",
		EncryptedMasterKeyForRecovery: "enc-recovery-2",
		Device: Device{
			DeviceID:   "device-2",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap after clearing state: %v", err)
	}
}

func TestFileStorePersistsDeviceApproval(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

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

	_, err = store.StartDeviceApproval(DeviceApprovalStartRequest{
		SessionToken:     session.SessionToken,
		ApprovalVerifier: "approval-proof",
		WrappedKeyBlob:   "wrapped-approval-key",
	})
	if err != nil {
		t.Fatalf("start approval: %v", err)
	}

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	approvedSession, err := reloadedStore.ConsumeDeviceApproval(DeviceApprovalConsumeRequest{
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

func TestFileStorePersistsDeviceLastSeen(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

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

	initialDevices, err := store.ListDevices(DeviceListRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("list devices before sync: %v", err)
	}
	if len(initialDevices) != 1 || initialDevices[0].LastSeenAt == "" {
		t.Fatal("expected bootstrap device to have a last-seen timestamp")
	}

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

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	devices, err := reloadedStore.ListDevices(DeviceListRequest{
		SessionToken: session.SessionToken,
	})
	if err != nil {
		t.Fatalf("list devices after reload: %v", err)
	}
	if len(devices) != 1 || devices[0].LastSeenAt == "" {
		t.Fatal("expected device last-seen timestamp to persist after reload")
	}
}

func TestFileStoreRejectsExpiredSessionsAcrossReload(t *testing.T) {
	tempDir := t.TempDir()
	filePath := filepath.Join(tempDir, "state.json")

	store, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("new file store: %v", err)
	}

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

	store.state.SessionIssuedAt[session.SessionToken] = "2026-01-01T00:00:00Z"
	if err := store.save(); err != nil {
		t.Fatalf("save expired session state: %v", err)
	}

	reloadedStore, err := NewFileStore(filePath)
	if err != nil {
		t.Fatalf("reload file store: %v", err)
	}

	_, err = reloadedStore.Pull(SyncPullRequest{SessionToken: session.SessionToken})
	if err == nil {
		t.Fatal("expected expired session to be rejected after reload")
	}
	if _, ok := reloadedStore.state.Sessions[session.SessionToken]; ok {
		t.Fatal("expected expired session to be pruned after reload")
	}
}
