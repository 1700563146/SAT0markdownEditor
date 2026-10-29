import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/l10n/app_localizations.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:mdreader/utils/app_style.dart';
import 'package:mdreader/utils/constants.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => 'C:/fake/documents';

  @override
  Future<String?> getApplicationSupportPath() async => 'C:/fake/support';

  @override
  Future<String?> getTemporaryPath() async => 'C:/tmp';
}

/// 用真实 SettingsProvider + 平台 mock 构建外观页测试环境。
///
/// 两点必须注意，否则断言会不可信：
/// - SliverList 只构建视口与 cacheExtent 内的子项，测试面要拉高到能容纳整页；
/// - SettingsProvider 的写入有 500ms 防抖 Timer，pumpAndSettle 只等帧不等 Timer，
///   不冲刷的话测试结束会报 pending timer。
Future<SettingsProvider> createAppearanceSettings() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = FakePathProviderPlatform();
  final settings = SettingsProvider();
  await settings.initialize();
  return settings;
}

Future<void> pumpAppearancePage(
  WidgetTester tester,
  SettingsProvider settings,
  Widget page, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1200, 9000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final scheme = ColorScheme.fromSeed(
    seedColor: SettingsProvider.themeColors.first,
    brightness: brightness,
  );
  final appStyle = AppStyleTheme.resolve(
    brightness: brightness,
    colorScheme: scheme,
    backgroundColor: scheme.surface,
    textSecondary: scheme.onSurfaceVariant,
    buttonStyleMode: AppButtonStyleMode.liquidGlass,
    cardOpacity: 0.8,
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        theme: ThemeData(
          colorScheme: scheme,
          brightness: brightness,
          extensions: [appStyle],
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

List<String> schemeNames({required bool dark}) =>
    (dark ? AppConstants.darkThemeSchemes : AppConstants.lightThemeSchemes)
        .map((s) => s.name)
        .toList();
