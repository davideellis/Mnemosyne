use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncCursor(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChangeKind {
    Note,
    Folder,
    Settings,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChangeOperation {
    Upsert,
    Move,
    Rename,
    Trash,
    Restore,
    DeleteFolder,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncChange {
    pub change_id: String,
    pub object_id: String,
    pub kind: ChangeKind,
    pub operation: ChangeOperation,
    pub logical_timestamp: String,
    pub origin_device_id: String,
    pub encrypted_metadata: String,
    pub encrypted_payload: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct SyncEnginePlan {
    pub outgoing_changes: Vec<SyncChange>,
    pub next_cursor: Option<SyncCursor>,
}

#[derive(Debug, Error)]
pub enum SyncPlanError {
    #[error("last-write-wins requires a logical timestamp for every change")]
    MissingTimestamp,
}

impl SyncEnginePlan {
    pub fn validate(&self) -> Result<(), SyncPlanError> {
        if self
            .outgoing_changes
            .iter()
            .any(|change| change.logical_timestamp.trim().is_empty())
        {
            return Err(SyncPlanError::MissingTimestamp);
        }

        Ok(())
    }
}
