use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeyEnvelope {
    pub encrypted_master_key_for_password: String,
    pub encrypted_master_key_for_recovery: String,
    pub password_kdf: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoveryMaterial {
    pub recovery_key_hint: Option<String>,
    pub recovery_key_fingerprint: String,
}

