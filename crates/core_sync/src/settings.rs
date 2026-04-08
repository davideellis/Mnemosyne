use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThemeMode {
    System,
    Light,
    Dark,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GraphSettings {
    pub show_labels: bool,
    pub highlight_backlinks: bool,
    pub depth_limit: u8,
}

impl Default for GraphSettings {
    fn default() -> Self {
        Self {
            show_labels: true,
            highlight_backlinks: true,
            depth_limit: 2,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppSettings {
    pub theme_mode: ThemeMode,
    pub sync_on_startup: bool,
    pub sync_over_metered_networks: bool,
    pub graph: GraphSettings,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme_mode: ThemeMode::System,
            sync_on_startup: true,
            sync_over_metered_networks: false,
            graph: GraphSettings::default(),
        }
    }
}

