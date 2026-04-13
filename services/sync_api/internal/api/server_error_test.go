package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

func TestRegisterDeviceRejectsInvalidSession(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/register", sync.DeviceRegistrationRequest{
		SessionToken: "invalid-session",
		Device: sync.Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected status %d, got %d", http.StatusUnauthorized, recorder.Code)
	}
}

func TestRestoreTrashReturnsNotFoundWhenObjectIsNotTrashed(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	session, err := store.Bootstrap(sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap failed: %v", err)
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/trash/restore", sync.RestoreTrashRequest{
		SessionToken: session.SessionToken,
		ObjectID:     "note-1",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d", http.StatusNotFound, recorder.Code)
	}
}

func TestRestoreTrashReturnsRestoredChange(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	session, err := store.Bootstrap(sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap failed: %v", err)
	}

	if _, err := store.Push(sync.SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []sync.SyncChange{
			{
				ChangeID:         "change-trash-1",
				ObjectID:         "note-1",
				Kind:             "note",
				Operation:        "trash",
				LogicalTimestamp: "2026-04-08T18:00:00Z",
			},
		},
	}); err != nil {
		t.Fatalf("push trash change: %v", err)
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/trash/restore", sync.RestoreTrashRequest{
		SessionToken: session.SessionToken,
		ObjectID:     "note-1",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestRevokeDeviceRejectsMissingDeviceID(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	session, err := store.Bootstrap(sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	if err != nil {
		t.Fatalf("bootstrap failed: %v", err)
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/revoke", sync.DeviceRevokeRequest{
		SessionToken: session.SessionToken,
		DeviceID:     "",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
}

func TestBootstrapRejectsMissingEmail(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/account/bootstrap", sync.AccountBootstrapRequest{
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "email is required")
}

func TestLoginRejectsMissingDevicePlatform(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/auth/login", sync.LoginRequest{
		Email:            "user@example.com",
		PasswordVerifier: "pw-proof",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "device.platform is required")
}

func TestStartApprovalRejectsMissingWrappedKeyBlob(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/approval/start", sync.DeviceApprovalStartRequest{
		SessionToken:     "session_bootstrap",
		ApprovalVerifier: "approval-proof",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "wrappedKeyBlob is required")
}

func TestPushRejectsMissingSessionToken(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		Changes: []sync.SyncChange{
			{
				ChangeID:         "change-1",
				ObjectID:         "note-1",
				Kind:             "note",
				Operation:        "upsert",
				LogicalTimestamp: "2026-04-08T18:00:00Z",
			},
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "sessionToken is required")
}

func TestPushRejectsUnsupportedChangeKind(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		SessionToken: "session-1",
		Changes: []sync.SyncChange{
			{
				ChangeID:          "change-1",
				ObjectID:          "note-1",
				Kind:              "binary",
				Operation:         "upsert",
				LogicalTimestamp:  "2026-04-08T18:00:00Z",
				OriginDeviceID:    "device-1",
				EncryptedMetadata: "meta",
				EncryptedPayload:  "payload",
			},
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "changes[0]: kind must be one of note, settings")
}

func TestPushRejectsInvalidTimestamp(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		SessionToken: "session-1",
		Changes: []sync.SyncChange{
			{
				ChangeID:          "change-1",
				ObjectID:          "note-1",
				Kind:              "note",
				Operation:         "upsert",
				LogicalTimestamp:  "yesterday-ish",
				OriginDeviceID:    "device-1",
				EncryptedMetadata: "meta",
				EncryptedPayload:  "payload",
			},
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "changes[0]: logicalTimestamp must be RFC3339 or RFC3339Nano")
}

func TestPushRejectsMissingEncryptedPayload(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		SessionToken: "session-1",
		Changes: []sync.SyncChange{
			{
				ChangeID:          "change-1",
				ObjectID:          "note-1",
				Kind:              "note",
				Operation:         "upsert",
				LogicalTimestamp:  "2026-04-08T18:00:00Z",
				OriginDeviceID:    "device-1",
				EncryptedMetadata: "meta",
			},
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "changes[0]: encryptedPayload is required")
}

func TestPushRejectsDuplicateChangeIDs(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		SessionToken: "session-1",
		Changes: []sync.SyncChange{
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
			{
				ChangeID:          "change-1",
				ObjectID:          "note-2",
				Kind:              "note",
				Operation:         "upsert",
				LogicalTimestamp:  "2026-04-08T18:01:00Z",
				OriginDeviceID:    "device-1",
				EncryptedMetadata: "meta-2",
				EncryptedPayload:  "payload-2",
			},
		},
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "changes[1]: duplicate changeId \"change-1\"")
}

func TestPushRejectsExcessiveBatchSize(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	changes := make([]sync.SyncChange, maxSyncPushChanges+1)
	for index := range changes {
		changes[index] = sync.SyncChange{
			ChangeID:          fmt.Sprintf("change-%d", index),
			ObjectID:          fmt.Sprintf("note-%d", index),
			Kind:              "note",
			Operation:         "upsert",
			LogicalTimestamp:  "2026-04-08T18:00:00Z",
			OriginDeviceID:    "device-1",
			EncryptedMetadata: "meta",
			EncryptedPayload:  "payload",
		}
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", sync.SyncPushRequest{
		SessionToken: "session-1",
		Changes:      changes,
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "changes may not exceed 256 entries")
}

func TestRestoreTrashRejectsMissingObjectID(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/trash/restore", sync.RestoreTrashRequest{
		SessionToken: "session_bootstrap",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
	assertAPIErrorMessage(t, recorder, "objectId is required")
}

func assertAPIErrorMessage(t *testing.T, recorder *httptest.ResponseRecorder, message string) {
	t.Helper()

	var body sync.APIError
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal error response: %v", err)
	}
	if body.Message != message {
		t.Fatalf("expected error message %q, got %q", message, body.Message)
	}
}
