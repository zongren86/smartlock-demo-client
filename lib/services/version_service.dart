import 'package:dio/dio.dart';
import 'package:smartlockdemo_client/config/app_config.dart';
import 'package:smartlockdemo_client/models/app_version.dart';

class VersionService {
  static const int currentVersionCode = 42;
  static const String currentVersionName = '1.0.42';
  static const String platform = 'android';

  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  final _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // 最多重试6次（间隔5s），覆盖 Render 约30s 冷启动
  Future<AppVersionInfo?> checkForUpdate() async {
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        final response = await _dio.get('/api/version/check', queryParameters: {
          'platform': platform,
          'currentVersionCode': currentVersionCode,
        });
        final info = AppVersionInfo.fromJson(response.data as Map<String, dynamic>);
        final shouldUpdate = info.hasUpdate &&
            (info.latestVersionCode == null || info.latestVersionCode! > currentVersionCode);
        return shouldUpdate ? info : null;
      } on DioException catch (e) {
        final isConnError = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (isConnError && attempt < 5) {
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        // 网络失败不阻断 App 启动
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
