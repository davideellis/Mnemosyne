use serde::{Deserialize, Serialize};

use crate::vault::VaultPath;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum TrashReason {
    UserDeleted,
    RemoteDeleted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrashEntry {
    pub object_id: String,
    pub original_path: VaultPath,
    pub deleted_at: String,
    pub reason: TrashReason,
}

