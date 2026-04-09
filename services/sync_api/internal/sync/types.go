package sync

type Device struct {
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
}

type AccountBootstrapRequest struct {
	Email                         string `json:"email"`
	PasswordVerifier              string `json:"passwordVerifier"`
	EncryptedMasterKeyForPassword string `json:"encryptedMasterKeyForPassword"`
	EncryptedMasterKeyForRecovery string `json:"encryptedMasterKeyForRecovery"`
	RecoveryKeyHint               string `json:"recoveryKeyHint"`
	Device                        Device `json:"device"`
}

type LoginRequest struct {
	Email            string `json:"email"`
	PasswordVerifier string `json:"passwordVerifier"`
}

type DeviceRegistrationRequest struct {
	SessionToken   string `json:"sessionToken"`
	Method         string `json:"method"`
	Device         Device `json:"device"`
	ApprovalCode   string `json:"approvalCode"`
	RecoveryProof  string `json:"recoveryProof"`
	WrappedKeyBlob string `json:"wrappedKeyBlob"`
}

type SyncChange struct {
	ChangeID          string `json:"changeId"`
	ObjectID          string `json:"objectId"`
	Kind              string `json:"kind"`
	Operation         string `json:"operation"`
	LogicalTimestamp  string `json:"logicalTimestamp"`
	OriginDeviceID    string `json:"originDeviceId"`
	EncryptedMetadata string `json:"encryptedMetadata"`
	EncryptedPayload  string `json:"encryptedPayload"`
}

type SyncPullRequest struct {
	SessionToken string `json:"sessionToken"`
	Cursor       string `json:"cursor"`
}

type SyncPushRequest struct {
	SessionToken string       `json:"sessionToken"`
	Cursor       string       `json:"cursor"`
	Changes      []SyncChange `json:"changes"`
}

type RestoreTrashRequest struct {
	SessionToken string `json:"sessionToken"`
	ObjectID     string `json:"objectId"`
}

type AuthSession struct {
	SessionToken                  string `json:"sessionToken"`
	AccountID                     string `json:"accountId"`
	EncryptedMasterKeyForPassword string `json:"encryptedMasterKeyForPassword,omitempty"`
	EncryptedMasterKeyForRecovery string `json:"encryptedMasterKeyForRecovery,omitempty"`
	RecoveryKeyHint               string `json:"recoveryKeyHint,omitempty"`
}

type PullResponse struct {
	Cursor  string       `json:"cursor"`
	Changes []SyncChange `json:"changes"`
}

type APIError struct {
	Message string `json:"message"`
}
