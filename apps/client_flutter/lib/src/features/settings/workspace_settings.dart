import 'dart:convert';

class WorkspaceSettings {
  const WorkspaceSettings({
    this.themeMode = 'system',
    this.colorPalette = 'emerald',
    this.autoSyncEnabled = true,
    this.backlinksEnabled = true,
    this.graphDepth = 2,
  });

  final String themeMode;
  final String colorPalette;
  final bool autoSyncEnabled;
  final bool backlinksEnabled;
  final int graphDepth;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeMode': themeMode,
      'colorPalette': colorPalette,
      'autoSyncEnabled': autoSyncEnabled,
      'backlinksEnabled': backlinksEnabled,
      'graphDepth': graphDepth,
    };
  }

  factory WorkspaceSettings.fromJson(Map<String, dynamic> json) {
    return WorkspaceSettings(
      themeMode: json['themeMode'] as String? ?? 'system',
      colorPalette: json['colorPalette'] as String? ?? 'emerald',
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      backlinksEnabled: json['backlinksEnabled'] as bool? ?? true,
      graphDepth: json['graphDepth'] as int? ?? 2,
    );
  }

  WorkspaceSettings copyWith({
    String? themeMode,
    String? colorPalette,
    bool? autoSyncEnabled,
    bool? backlinksEnabled,
    int? graphDepth,
  }) {
    return WorkspaceSettings(
      themeMode: themeMode ?? this.themeMode,
      colorPalette: colorPalette ?? this.colorPalette,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      backlinksEnabled: backlinksEnabled ?? this.backlinksEnabled,
      graphDepth: graphDepth ?? this.graphDepth,
    );
  }

  String digest() => jsonEncode(toJson());
}
