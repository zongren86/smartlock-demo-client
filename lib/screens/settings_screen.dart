import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/models/app_version.dart';
import 'package:smartlockdemo_client/services/version_service.dart';
import 'package:smartlockdemo_client/utils/toast.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await VersionService().checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        showCenterToast(context, S.read(context).alreadyLatest);
      } else {
        _showUpdateDialog(info);
      }
    } catch (_) {
      if (mounted) showCenterToast(context, S.read(context).checkUpdateFailed);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showUpdateDialog(AppVersionInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (_) => _UpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = context.watch<LocaleNotifier>();
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(s.settings),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(s.about, [
            _buildInfoTile(
              Icons.info_outline,
              s.currentVersion,
              'v${VersionService.currentVersionName} (${VersionService.currentVersionCode})',
            ),
          ]),
          const SizedBox(height: 12),
          _buildSection(s.language, [
            _buildTapTile(
              Icons.language,
              s.switchLanguage,
              locale.isEn ? s.english : s.chinese,
              trailing: Text(
                locale.isEn ? 'EN' : '中',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8)),
              ),
              onTap: () => locale.setLang(locale.isEn ? 'zh' : 'en'),
            ),
          ]),
          const SizedBox(height: 12),
          _buildSection(s.updates, [
            _buildTapTile(
              Icons.system_update_outlined,
              s.checkUpdate,
              s.checkUpdateSub,
              trailing: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
              onTap: _checking ? null : _checkUpdate,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: const Color(0xFF1A73E8)),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
    );
  }

  Widget _buildTapTile(IconData icon, String label, String subtitle,
      {Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: const Color(0xFF1A73E8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: const Color(0xFF1A73E8)),
      ),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

// ── 应用内下载 + 安装弹窗 ────────────────────────────────────────────────────

enum _DownloadPhase { idle, downloading, done, failed }

class _UpdateDialog extends StatefulWidget {
  final AppVersionInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _DownloadPhase _phase = _DownloadPhase.idle;
  int _progress = 0;
  String? _savePath;
  String? _errorMsg;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final url = widget.info.downloadUrl;
    if (url == null || url.isEmpty) return;

    // Request install permission on Android 8+
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted && mounted) {
        showCenterToast(context, S.read(context).installPermissionDenied);
        return;
      }
    }

    setState(() { _phase = _DownloadPhase.downloading; _progress = 0; _errorMsg = null; });

    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final path = '${dir.path}/smartlock_update.apk';
      _cancelToken = CancelToken();

      await Dio().download(
        url,
        path,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = ((received / total) * 100).round());
          }
        },
        options: Options(followRedirects: true, maxRedirects: 5),
      );

      _savePath = path;
      if (mounted) setState(() => _phase = _DownloadPhase.done);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (mounted) setState(() { _phase = _DownloadPhase.failed; _errorMsg = e.message; });
    } catch (e) {
      if (mounted) setState(() { _phase = _DownloadPhase.failed; _errorMsg = e.toString(); });
    }
  }

  Future<void> _install() async {
    if (_savePath == null) return;
    setState(() => _phase = _DownloadPhase.idle);
    final result = await OpenFile.open(_savePath!);
    if (result.type != ResultType.done && mounted) {
      showCenterToast(context, S.read(context).cannotOpenInstaller);
      setState(() => _phase = _DownloadPhase.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final canDismiss = !widget.info.forceUpdate && _phase != _DownloadPhase.downloading;

    return PopScope(
      canPop: canDismiss,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF1A73E8), size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(s.newVersionFound(widget.info.latestVersionName ?? ''),
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.info.forceUpdate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(s.forceUpdateNote,
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  ),
                if (widget.info.releaseNotes != null) ...[
                  Text(s.whatsNew,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(widget.info.releaseNotes!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                ],
                if (_phase == _DownloadPhase.downloading) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress / 100 : null,
                    backgroundColor: Colors.grey.shade200,
                    color: const Color(0xFF1A73E8),
                  ),
                  const SizedBox(height: 6),
                  Text(s.downloadProgress(_progress),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
                if (_phase == _DownloadPhase.done) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.downloadDone,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF10B981)))),
                      ],
                    ),
                  ),
                ],
                if (_phase == _DownloadPhase.failed && _errorMsg != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_errorMsg!,
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: _buildActions(s),
      ),
    );
  }

  List<Widget> _buildActions(S s) {
    switch (_phase) {
      case _DownloadPhase.idle:
        return [
          if (!widget.info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.updateLater),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: Text(s.updateNow),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
            ),
            onPressed: _startDownload,
          ),
        ];

      case _DownloadPhase.downloading:
        return [
          TextButton(
            onPressed: () {
              _cancelToken?.cancel();
              if (!widget.info.forceUpdate && mounted) Navigator.pop(context);
            },
            child: Text(s.cancel),
          ),
        ];

      case _DownloadPhase.done:
        return [
          ElevatedButton.icon(
            icon: const Icon(Icons.install_mobile, size: 18),
            label: Text(s.installNow),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: _install,
          ),
        ];

      case _DownloadPhase.failed:
        return [
          if (!widget.info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel),
            ),
          ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
            ),
            child: Text(s.retryDownload),
          ),
        ];
    }
  }
}
