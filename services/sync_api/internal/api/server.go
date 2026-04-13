package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

type Store interface {
	Bootstrap(req sync.AccountBootstrapRequest) (sync.AuthSession, error)
	Login(req sync.LoginRequest) (sync.AuthSession, error)
	Logout(req sync.LogoutRequest) error
	Recover(req sync.RecoveryRequest) (sync.AuthSession, error)
	RegisterDevice(req sync.DeviceRegistrationRequest) (sync.Device, error)
	ListDevices(req sync.DeviceListRequest) ([]sync.Device, error)
	RevokeDevice(req sync.DeviceRevokeRequest) error
	StartDeviceApproval(req sync.DeviceApprovalStartRequest) (sync.DeviceApproval, error)
	ConsumeDeviceApproval(req sync.DeviceApprovalConsumeRequest) (sync.AuthSession, error)
	Pull(req sync.SyncPullRequest) (sync.PullResponse, error)
	Push(req sync.SyncPushRequest) (sync.PullResponse, error)
	RestoreTrash(req sync.RestoreTrashRequest) (sync.SyncChange, error)
}

type Server struct {
	store     Store
	buildInfo BuildInfo
}

type BuildInfo struct {
	BuildSHA string `json:"buildSha,omitempty"`
	AWSMode  string `json:"awsMode,omitempty"`
}

const maxSyncPushChanges = 256

var requestCounter uint64

func NewServer(store Store, options ...func(*Server)) *Server {
	server := &Server{store: store}
	for _, option := range options {
		option(server)
	}
	return server
}

func WithBuildInfo(buildInfo BuildInfo) func(*Server) {
	return func(server *Server) {
		server.buildInfo = buildInfo
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("POST /v1/account/bootstrap", s.handleBootstrap)
	mux.HandleFunc("POST /v1/auth/login", s.handleLogin)
	mux.HandleFunc("POST /v1/auth/logout", s.handleLogout)
	mux.HandleFunc("POST /v1/auth/recover", s.handleRecover)
	mux.HandleFunc("POST /v1/devices/register", s.handleRegisterDevice)
	mux.HandleFunc("POST /v1/devices/list", s.handleListDevices)
	mux.HandleFunc("POST /v1/devices/revoke", s.handleRevokeDevice)
	mux.HandleFunc("POST /v1/devices/approval/start", s.handleStartDeviceApproval)
	mux.HandleFunc("POST /v1/devices/approval/consume", s.handleConsumeDeviceApproval)
	mux.HandleFunc("POST /v1/sync/pull", s.handlePull)
	mux.HandleFunc("POST /v1/sync/push", s.handlePush)
	mux.HandleFunc("POST /v1/trash/restore", s.handleRestoreTrash)
	return withRequestLogging(withPanicRecovery(withJSON(mux)))
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req sync.LogoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateLogoutRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := s.store.Logout(req); err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidSession) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *Server) handleListDevices(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceListRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateDeviceListRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	devices, err := s.store.ListDevices(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidSession) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func (s *Server) handleRevokeDevice(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceRevokeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateDeviceRevokeRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := s.store.RevokeDevice(req); err != nil {
		status := http.StatusInternalServerError
		switch {
		case errors.Is(err, sync.ErrInvalidSession):
			status = http.StatusUnauthorized
		case errors.Is(err, sync.ErrInvalidDevice):
			status = http.StatusBadRequest
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *Server) handleStartDeviceApproval(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceApprovalStartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateDeviceApprovalStartRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	approval, err := s.store.StartDeviceApproval(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidSession) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusCreated, approval)
}

func (s *Server) handleConsumeDeviceApproval(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceApprovalConsumeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateDeviceApprovalConsumeRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	session, err := s.store.ConsumeDeviceApproval(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidApproval) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) handleRecover(w http.ResponseWriter, r *http.Request) {
	var req sync.RecoveryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateRecoveryRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	session, err := s.store.Recover(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidCredentials) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":   "ok",
		"buildSha": s.buildInfo.BuildSHA,
		"awsMode":  s.buildInfo.AWSMode,
	})
}

func (s *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	var req sync.AccountBootstrapRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateBootstrapRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	session, err := s.store.Bootstrap(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrAccountExists) {
			status = http.StatusConflict
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusCreated, session)
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req sync.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateLoginRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	session, err := s.store.Login(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidCredentials) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceRegistrationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateDeviceRegistrationRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	device, err := s.store.RegisterDevice(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidSession) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusCreated, device)
}

func (s *Server) handlePull(w http.ResponseWriter, r *http.Request) {
	var req sync.SyncPullRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateSyncPullRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	response, err := s.store.Pull(req)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, sync.ErrInvalidSession) {
			status = http.StatusUnauthorized
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, response)
}

func (s *Server) handlePush(w http.ResponseWriter, r *http.Request) {
	var req sync.SyncPushRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateSyncPushRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	response, err := s.store.Push(req)
	if err != nil {
		status := http.StatusInternalServerError
		switch {
		case errors.Is(err, sync.ErrInvalidSession):
			status = http.StatusUnauthorized
		case errors.Is(err, sync.ErrChangeRejected):
			status = http.StatusUnprocessableEntity
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusAccepted, response)
}

func (s *Server) handleRestoreTrash(w http.ResponseWriter, r *http.Request) {
	var req sync.RestoreTrashRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateRestoreTrashRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	change, err := s.store.RestoreTrash(req)
	if err != nil {
		status := http.StatusInternalServerError
		switch {
		case errors.Is(err, sync.ErrInvalidSession):
			status = http.StatusUnauthorized
		case errors.Is(err, sync.ErrObjectNotInTrash):
			status = http.StatusNotFound
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusOK, change)
}

func withJSON(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		next.ServeHTTP(w, r)
	})
}

func withRequestLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := nextRequestID()
		startedAt := time.Now()
		w.Header().Set("X-Mnemosyne-Request-Id", requestID)

		recorder := &statusRecorder{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}
		next.ServeHTTP(recorder, r)

		log.Printf(
			"request_id=%s method=%s path=%s status=%d duration_ms=%d remote_addr=%q",
			requestID,
			r.Method,
			r.URL.Path,
			recorder.statusCode,
			time.Since(startedAt).Milliseconds(),
			r.RemoteAddr,
		)
	})
}

func withPanicRecovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				log.Printf("panic while handling %s %s: %v", r.Method, r.URL.Path, recovered)
				writeJSON(w, http.StatusInternalServerError, sync.APIError{
					Message: "internal server error",
				})
			}
		}()

		next.ServeHTTP(w, r)
	})
}

func nextRequestID() string {
	value := atomic.AddUint64(&requestCounter, 1)
	return fmt.Sprintf("req-%d-%d", time.Now().UTC().UnixMilli(), value)
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (r *statusRecorder) WriteHeader(statusCode int) {
	r.statusCode = statusCode
	r.ResponseWriter.WriteHeader(statusCode)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, sync.APIError{Message: err.Error()})
}

func validateBootstrapRequest(req sync.AccountBootstrapRequest) error {
	if req.Email == "" {
		return fmt.Errorf("email is required")
	}
	if req.PasswordVerifier == "" {
		return fmt.Errorf("passwordVerifier is required")
	}
	if req.RecoveryVerifier == "" {
		return fmt.Errorf("recoveryVerifier is required")
	}
	if req.EncryptedMasterKeyForPassword == "" {
		return fmt.Errorf("encryptedMasterKeyForPassword is required")
	}
	if req.EncryptedMasterKeyForRecovery == "" {
		return fmt.Errorf("encryptedMasterKeyForRecovery is required")
	}
	return validateDevice(req.Device)
}

func validateLoginRequest(req sync.LoginRequest) error {
	if req.Email == "" {
		return fmt.Errorf("email is required")
	}
	if req.PasswordVerifier == "" {
		return fmt.Errorf("passwordVerifier is required")
	}
	return validateDevice(req.Device)
}

func validateLogoutRequest(req sync.LogoutRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	return nil
}

func validateRecoveryRequest(req sync.RecoveryRequest) error {
	if req.Email == "" {
		return fmt.Errorf("email is required")
	}
	if req.RecoveryVerifier == "" {
		return fmt.Errorf("recoveryVerifier is required")
	}
	return validateDevice(req.Device)
}

func validateDeviceRegistrationRequest(req sync.DeviceRegistrationRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	return validateDevice(req.Device)
}

func validateDeviceApprovalStartRequest(req sync.DeviceApprovalStartRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	if req.ApprovalVerifier == "" {
		return fmt.Errorf("approvalVerifier is required")
	}
	if req.WrappedKeyBlob == "" {
		return fmt.Errorf("wrappedKeyBlob is required")
	}
	return nil
}

func validateDeviceApprovalConsumeRequest(req sync.DeviceApprovalConsumeRequest) error {
	if req.Email == "" {
		return fmt.Errorf("email is required")
	}
	if req.ApprovalVerifier == "" {
		return fmt.Errorf("approvalVerifier is required")
	}
	return validateDevice(req.Device)
}

func validateDeviceListRequest(req sync.DeviceListRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	return nil
}

func validateDeviceRevokeRequest(req sync.DeviceRevokeRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	if req.DeviceID == "" {
		return fmt.Errorf("deviceId is required")
	}
	return nil
}

func validateSyncPullRequest(req sync.SyncPullRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	return nil
}

func validateSyncPushRequest(req sync.SyncPushRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	if len(req.Changes) > maxSyncPushChanges {
		return fmt.Errorf("changes may not exceed %d entries", maxSyncPushChanges)
	}
	seenChangeIDs := make(map[string]struct{}, len(req.Changes))
	for index, change := range req.Changes {
		if _, exists := seenChangeIDs[change.ChangeID]; exists && change.ChangeID != "" {
			return fmt.Errorf("changes[%d]: duplicate changeId %q", index, change.ChangeID)
		}
		if change.ChangeID != "" {
			seenChangeIDs[change.ChangeID] = struct{}{}
		}
		if err := validateSyncChange(change); err != nil {
			return fmt.Errorf("changes[%d]: %w", index, err)
		}
	}
	return nil
}

func validateRestoreTrashRequest(req sync.RestoreTrashRequest) error {
	if req.SessionToken == "" {
		return fmt.Errorf("sessionToken is required")
	}
	if req.ObjectID == "" {
		return fmt.Errorf("objectId is required")
	}
	return nil
}

func validateDevice(device sync.Device) error {
	if device.DeviceID == "" {
		return fmt.Errorf("device.deviceId is required")
	}
	if device.DeviceName == "" {
		return fmt.Errorf("device.deviceName is required")
	}
	if device.Platform == "" {
		return fmt.Errorf("device.platform is required")
	}
	return nil
}

func validateSyncChange(change sync.SyncChange) error {
	if change.ChangeID == "" {
		return fmt.Errorf("changeId is required")
	}
	if change.ObjectID == "" {
		return fmt.Errorf("objectId is required")
	}
	switch change.Kind {
	case "note", "settings":
	default:
		return fmt.Errorf("kind must be one of note, settings")
	}
	switch change.Operation {
	case "upsert", "trash", "restore":
	default:
		return fmt.Errorf("operation must be one of upsert, trash, restore")
	}
	if change.LogicalTimestamp == "" {
		return fmt.Errorf("logicalTimestamp is required")
	}
	if parseTime := syncTime(change.LogicalTimestamp); parseTime.IsZero() {
		return fmt.Errorf("logicalTimestamp must be RFC3339 or RFC3339Nano")
	}
	if change.OriginDeviceID == "" {
		return fmt.Errorf("originDeviceId is required")
	}
	if change.EncryptedMetadata == "" {
		return fmt.Errorf("encryptedMetadata is required")
	}
	if change.EncryptedPayload == "" {
		return fmt.Errorf("encryptedPayload is required")
	}
	return nil
}

func syncTime(value string) time.Time {
	if parsed, err := time.Parse(time.RFC3339Nano, value); err == nil {
		return parsed.UTC()
	}
	if parsed, err := time.Parse(time.RFC3339, value); err == nil {
		return parsed.UTC()
	}
	return time.Time{}
}
