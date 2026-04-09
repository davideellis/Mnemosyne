package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

type Store interface {
	Bootstrap(req sync.AccountBootstrapRequest) (sync.AuthSession, error)
	Login(req sync.LoginRequest) (sync.AuthSession, error)
	Recover(req sync.RecoveryRequest) (sync.AuthSession, error)
	RegisterDevice(req sync.DeviceRegistrationRequest) (sync.Device, error)
	ListDevices(req sync.DeviceListRequest) ([]sync.Device, error)
	StartDeviceApproval(req sync.DeviceApprovalStartRequest) (sync.DeviceApproval, error)
	ConsumeDeviceApproval(req sync.DeviceApprovalConsumeRequest) (sync.AuthSession, error)
	Pull(req sync.SyncPullRequest) (sync.PullResponse, error)
	Push(req sync.SyncPushRequest) (sync.PullResponse, error)
	RestoreTrash(req sync.RestoreTrashRequest) (sync.SyncChange, error)
}

type Server struct {
	store Store
}

func NewServer(store Store) *Server {
	return &Server{store: store}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("POST /v1/account/bootstrap", s.handleBootstrap)
	mux.HandleFunc("POST /v1/auth/login", s.handleLogin)
	mux.HandleFunc("POST /v1/auth/recover", s.handleRecover)
	mux.HandleFunc("POST /v1/devices/register", s.handleRegisterDevice)
	mux.HandleFunc("POST /v1/devices/list", s.handleListDevices)
	mux.HandleFunc("POST /v1/devices/approval/start", s.handleStartDeviceApproval)
	mux.HandleFunc("POST /v1/devices/approval/consume", s.handleConsumeDeviceApproval)
	mux.HandleFunc("POST /v1/sync/pull", s.handlePull)
	mux.HandleFunc("POST /v1/sync/push", s.handlePush)
	mux.HandleFunc("POST /v1/trash/restore", s.handleRestoreTrash)
	return withJSON(mux)
}

func (s *Server) handleListDevices(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceListRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
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

func (s *Server) handleStartDeviceApproval(w http.ResponseWriter, r *http.Request) {
	var req sync.DeviceApprovalStartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
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
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleBootstrap(w http.ResponseWriter, r *http.Request) {
	var req sync.AccountBootstrapRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
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

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, sync.APIError{Message: err.Error()})
}
