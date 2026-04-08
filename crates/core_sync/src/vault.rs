use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VaultPath(pub String);

impl VaultPath {
    pub fn new(path: impl Into<String>) -> Self {
        Self(path.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoteDocument {
    pub object_id: String,
    pub path: VaultPath,
    pub title: String,
    pub markdown: String,
    pub tags: Vec<String>,
    pub wikilinks: Vec<String>,
    pub logical_timestamp: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FolderNode {
    pub object_id: String,
    pub path: VaultPath,
    pub logical_timestamp: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct VaultManifest {
    pub notes: Vec<NoteDocument>,
    pub folders: Vec<FolderNode>,
}

