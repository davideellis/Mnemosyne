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
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	if session.SessionToken == "" {
		t.Fatal("expected recovery to return a session token")
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
