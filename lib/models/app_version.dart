class AppVersionInfo {
  final bool hasUpdate;
  final int? latestVersionCode;
  final String? latestVersionName;
  final String? downloadUrl;
  final bool forceUpdate;
  final String? releaseNotes;

  const AppVersionInfo({
    required this.hasUpdate,
    this.latestVersionCode,
    this.latestVersionName,
    this.downloadUrl,
    this.forceUpdate = false,
    this.releaseNotes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      hasUpdate: json['hasUpdate'] as bool? ?? false,
      latestVersionCode: json['latestVersionCode'] as int?,
      latestVersionName: json['latestVersionName'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }
}
