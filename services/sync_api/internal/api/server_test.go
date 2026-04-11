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
	if recorder.Header().Get("X-Mnemosyne-Request-Id") == "" {
		t.Fatal("expected request id header on bootstrap response")
	}

	loginBody := sync.LoginRequest{
		Email:            "user@example.com",
		PasswordVerifier: "pw-proof",
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/auth/login", loginBody)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
}

func TestHealthIncludesRequestIDHeader(t *testing.T) {
	server := NewServer(
		sync.NewMemoryStore(),
		WithBuildInfo(BuildInfo{
			BuildSHA: "abc123",
			AWSMode:  "lambda",
		}),
	)

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	server.Routes().ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}
	if recorder.Header().Get("X-Mnemosyne-Request-Id") == "" {
		t.Fatal("expected request id header on health response")
	}

	var body map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal health response: %v", err)
	}
	if body["buildSha"] != "abc123" {
		t.Fatalf("expected build sha in health response, got %q", body["buildSha"])
	}
	if body["awsMode"] != "lambda" {
		t.Fatalf("expected aws mode in health response, got %q", body["awsMode"])
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
		Device: sync.Device{
			DeviceID:   "device-1",
			DeviceName: "Windows Laptop",
			Platform:   "windows",
		},
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

func TestRevokeDevice(t *testing.T) {
	store := sync.NewMemoryStore()
	server := NewServer(store)

	bootstrapSession, err := store.Bootstrap(sync.AccountBootstrapRequest{
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

	recoverySession, err := store.Recover(sync.RecoveryRequest{
		Email:            "user@example.com",
		RecoveryVerifier: "rec-proof",
		Device: sync.Device{
			DeviceID:   "device-2",
			DeviceName: "Mac Desktop",
			Platform:   "macos",
		},
	})
	if err != nil {
		t.Fatalf("recover failed: %v", err)
	}

	recorder := httptest.NewRecorder()
	request := newJSONRequest(t, http.MethodPost, "/v1/devices/revoke", sync.DeviceRevokeRequest{
		SessionToken: bootstrapSession.SessionToken,
		DeviceID:     "device-2",
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/devices/list", sync.DeviceListRequest{
		SessionToken: bootstrapSession.SessionToken,
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	recorder = httptest.NewRecorder()
	request = newJSONRequest(t, http.MethodPost, "/v1/sync/pull", sync.SyncPullRequest{
		SessionToken: recoverySession.SessionToken,
	})
	server.Routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected revoked session to return %d, got %d", http.StatusUnauthorized, recorder.Code)
	}
}

func TestLogout(t *testing.T) {
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
	request := newJSONRequest(t, http.MethodPost, "/v1/auth/logout", sync.LogoutRequest{
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
