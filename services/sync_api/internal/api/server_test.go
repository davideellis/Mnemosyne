package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

func TestBootstrapAndLogin(t *testing.T) {
	server := NewServer(sync.NewMemoryStore())

	bootstrapBody := sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		RecoveryKeyHint:               "first pet",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/account/bootstrap", bootstrapBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, recorder.Code)
	}

	loginBody := sync.LoginRequest{
		Email:            "user@example.com",
		PasswordVerifier: "pw-proof",
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/auth/login", loginBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestRecover(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	_, err := store.Bootstrap(sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		RecoveryKeyHint:               "first pet",
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
	request := newJSONRequest(t, http.MethodPost, "/v1/auth/recover", sync.RecoveryRequest{
		Email:            "user@example.com",
		RecoveryVerifier: "rec-proof",
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestDeviceApprovalStartAndConsume(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	session, err := store.Bootstrap(sync.AccountBootstrapRequest{
		Email:                         "user@example.com",
		PasswordVerifier:              "pw-proof",
		RecoveryVerifier:              "rec-proof",
		EncryptedMasterKeyForPassword: "enc-pw",
		EncryptedMasterKeyForRecovery: "enc-recovery",
		RecoveryKeyHint:               "first pet",
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
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/approval/start", sync.DeviceApprovalStartRequest{
		SessionToken:     session.SessionToken,
		ApprovalVerifier: "approval-proof",
		WrappedKeyBlob:   "wrapped-key",
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, recorder.Code)
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/devices/approval/consume", sync.DeviceApprovalConsumeRequest{
		Email:            "user@example.com",
		ApprovalVerifier: "approval-proof",
		Device: sync.Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestListDevices(t *testing.T) {
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
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/list", sync.DeviceListRequest{
		SessionToken: session.SessionToken,
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestPushThenPull(t *testing.T) {
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

	pushBody := sync.SyncPushRequest{
		SessionToken: session.SessionToken,
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
		},
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", pushBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusAccepted {
		t.Fatalf("expected status %d, got %d", http.StatusAccepted, recorder.Code)
	}

	pullBody := sync.SyncPullRequest{
		SessionToken: session.SessionToken,
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/sync/pull", pullBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var response sync.PullResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if len(response.Changes) != 1 {
		t.Fatalf("expected 1 change, got %d", len(response.Changes))
	}
	if response.Changes[0].ObjectID != "note-1" {
		t.Fatalf("expected note-1, got %s", response.Changes[0].ObjectID)
	}
}

func TestPushIgnoresStaleChangeForSameObject(t *testing.T) {
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

	pushBody := sync.SyncPushRequest{
		SessionToken: session.SessionToken,
		Changes: []sync.SyncChange{
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
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/sync/push", pushBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusAccepted {
		t.Fatalf("expected status %d, got %d", http.StatusAccepted, recorder.Code)
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/sync/pull", sync.SyncPullRequest{
		SessionToken: session.SessionToken,
	})
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var response sync.PullResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if len(response.Changes) != 1 {
		t.Fatalf("expected 1 accepted change, got %d", len(response.Changes))
	}
	if response.Changes[0].ChangeID != "change-2" {
		t.Fatalf("expected latest change to survive, got %s", response.Changes[0].ChangeID)
	}
}

func newJSONRequest(t *testing.T, method string, path string, body any) *http.Request {
	t.Helper()

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	request := httptest.NewRequest(method, path, bytes.NewReader(payload))
	request.Header.Set("Content-Type", "application/json")
	return request
}
