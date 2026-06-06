import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/models/app_version.dart';
import 'package:smartlockdemo_client/screens/home_screen.dart';
import 'package:smartlockdemo_client/services/version_service.dart';
import 'package:smartlockdemo_client/services/wx_pay_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.warning);
  await WxPayService().init();
  final localeNotifier = LocaleNotifier();
  await localeNotifier.load();
  runApp(SmartLockApp(localeNotifier: localeNotifier));
}

class SmartLockApp extends StatelessWidget {
  final LocaleNotifier localeNotifier;
  const SmartLockApp({super.key, required this.localeNotifier});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider.value(value: localeNotifier),
      ],
      child: Consumer<LocaleNotifier>(
        builder: (_, locale, __) => MaterialApp(
          title: 'SmartLock',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          locale: Locale(locale.lang),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1A73E8),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
            ),
          ),
          home: const AppEntryPoint(),
        ),
      ),
    );
  }
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final update = await VersionService().checkForUpdate();
    if (update != null && mounted) {
      _showUpdateDialog(update);
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
  Widget build(BuildContext context) => const HomeScreen();
}

// ── 应用内更新下载弹窗 ─────────────────────────────────────────────────────

enum _DownloadPhase { idle, downloading, downloaded, installing, error }

class _UpdateDialog extends StatefulWidget {
  final AppVersionInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _DownloadPhase _phase = _DownloadPhase.idle;
  double _progress = 0;
  String? _errorMsg;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  String? _apkPath;

  Future<void> _startDownload() async {
    if (widget.info.downloadUrl == null) return;
    setState(() { _phase = _DownloadPhase.downloading; _progress = 0; _errorMsg = null; });
    try {
      // Use external app directory — more reliable for APK installation than temp
      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory() ?? await getTemporaryDirectory()
          : await getTemporaryDirectory();
      _apkPath = '${dir.path}/smartlock_update.apk';
      _cancelToken = CancelToken();
      await Dio().download(
        widget.info.downloadUrl!,
        _apkPath!,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() => _phase = _DownloadPhase.downloaded);
    } catch (e) {
      if (mounted) setState(() { _phase = _DownloadPhase.error; _errorMsg = e.toString(); });
    }
  }

  Future<void> _installApk() async {
    if (_apkPath == null) return;
    setState(() { _phase = _DownloadPhase.installing; _errorMsg = null; });
    try {
      // Android 8+ requires explicit per-app install permission
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          // Opens the "Install unknown apps" settings page for this app
          await Permission.requestInstallPackages.request();
          // After user returns, check again
          final updated = await Permission.requestInstallPackages.status;
          if (!updated.isGranted) {
            if (mounted) setState(() {
              _phase = _DownloadPhase.downloaded;
              _errorMsg = S.read(context).installPermissionDenied;
            });
            return;
          }
        }
      }
      final result = await OpenFile.open(
        _apkPath!,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _phase = _DownloadPhase.downloaded;
          _errorMsg = '${S.read(context).cannotOpenInstaller}: ${result.message}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _phase = _DownloadPhase.downloaded; _errorMsg = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.info.forceUpdate && _phase != _DownloadPhase.downloading,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFF1A73E8), size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(
                S.of(context).newVersionFound(widget.info.latestVersionName ?? ''),
                style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.info.forceUpdate)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber, color: Colors.red, size: 15),
                      const SizedBox(width: 6),
                      Text(S.of(context).forceUpdateNote,
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ]),
                  ),
                if (widget.info.releaseNotes != null) ...[
                  Text(S.of(context).whatsNew,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(widget.info.releaseNotes!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
                ],
                if (_phase == _DownloadPhase.downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress, minHeight: 6,
                      borderRadius: BorderRadius.circular(3)),
                  const SizedBox(height: 6),
                  Text(S.of(context).downloadProgress((_progress * 100).toInt()),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
                if (_phase == _DownloadPhase.downloaded) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 6),
                    Text(S.of(context).downloadDone,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF10B981))),
                  ]),
                ],
                if (_phase == _DownloadPhase.installing) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(S.of(context).installing, style: const TextStyle(fontSize: 13)),
                  ]),
                ],
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMsg!,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!widget.info.forceUpdate && _phase != _DownloadPhase.downloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context).updateLater),
            ),
          if (_phase == _DownloadPhase.idle || _phase == _DownloadPhase.error)
            ElevatedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: Text(_phase == _DownloadPhase.error
                  ? S.of(context).retryDownload
                  : S.of(context).updateNow),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
              ),
              onPressed: _startDownload,
            ),
          if (_phase == _DownloadPhase.downloaded)
            ElevatedButton.icon(
              icon: const Icon(Icons.install_mobile, size: 18),
              label: Text(S.of(context).installNow),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: _installApk,
            ),
          if (_phase == _DownloadPhase.installing)
            ElevatedButton.icon(
              icon: const Icon(Icons.install_mobile, size: 18),
              label: Text(S.of(context).installingBtn),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981).withOpacity(0.6),
                foregroundColor: Colors.white,
              ),
              onPressed: null,
            ),
          if (_phase == _DownloadPhase.downloading)
            TextButton(
              onPressed: () { _cancelToken?.cancel(); setState(() => _phase = _DownloadPhase.idle); },
              child: Text(S.of(context).cancel),
            ),
        ],
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  String _userId = 'demo_user_001';
  String get userId => _userId;
  set userId(String v) { _userId = v; notifyListeners(); }
}
