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
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	if session.SessionToken == "" {
		t.Fatal("expected recovery to return a session token")
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
