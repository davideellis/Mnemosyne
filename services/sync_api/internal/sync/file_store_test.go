package sync

import (
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
