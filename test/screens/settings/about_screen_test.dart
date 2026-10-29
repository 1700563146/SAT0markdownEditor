import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdreader/screens/settings/about_screen.dart';
import 'package:mdreader/screens/settings/open_source_licenses_screen.dart';
import 'package:mdreader/services/update_service.dart';
import 'package:mdreader/providers/settings_provider.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

// Mock dependencies
class MockUpdateService extends Mock implements UpdateService {}
class MockHttpClient extends Mock implements http.Client {}

// Mock SettingsProvider
// Using a real ChangeNotifier for simplicity as we just need it to exist in the context
// Mock SettingsProvider
// Using a real ChangeNotifier for simplicity as we just need it to exist in the context
class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  // Theme
  ThemeMode _themeMode = ThemeMode.system;
  int _primaryColorIndex = 0;
  int _darkThemeIndex = 0;
  int _lightThemeIndex = 0;
  String _uiFontFamily = 'System';
  String _editorFontFamily = 'System';
  String _codeFontFamily = 'System';
  
  // Editor
  double _fontSize = 16.0;
  bool _autoSave = true;
  int _autoSaveInterval = 2;
  String? _defaultDirectory;
  
  // Background
  String? _backgroundImagePath;
  String _backgroundEffect = 'none';
  double _backgroundBlur = 10.0;
  
  // Cloud
  String _webdavUrl = '';
  String _webdavUsername = '';
  String _webdavPassword = '';
  bool _autoSyncEnabled = false;
  DateTime? _lastSyncTime;
  bool _autoCheckUpdate = true;
  String _updateChannel = 'stable';

  // Getters
  @override ThemeMode get themeMode => _themeMode;
  @override int get primaryColorIndex => _primaryColorIndex;
  @override Color get primaryColor => Colors.blue; // Mock return
  @override int get darkThemeIndex => _darkThemeIndex;
  @override int get lightThemeIndex => _lightThemeIndex;
  @override String get uiFontFamily => _uiFontFamily;
  @override String get editorFontFamily => _editorFontFamily;
  @override String get codeFontFamily => _codeFontFamily;
  
  @override double get fontSize => _fontSize;
  @override bool get autoSave => _autoSave;
  @override int get autoSaveInterval => _autoSaveInterval;
  @override String? get defaultDirectory => _defaultDirectory;
  
  @override String? get backgroundImagePath => _backgroundImagePath;
  @override String get backgroundEffect => _backgroundEffect;
  @override double get backgroundBlur => _backgroundBlur;
  
  @override Locale get locale => const Locale('zh');
  
  @override String get webdavUrl => _webdavUrl;
  @override String get webdavUsername => _webdavUsername;
  @override String get webdavPassword => _webdavPassword;
  @override bool get autoSyncEnabled => _autoSyncEnabled;
  @override DateTime? get lastSyncTime => _lastSyncTime;
  @override bool get isWebdavConfigured => false;
  @override bool get autoCheckUpdate => _autoCheckUpdate;
  @override String get updateChannel => _updateChannel;

  @override void loadSettings() {}
  @override Future<void> setAutoCheckUpdate(bool value) async { _autoCheckUpdate = value; }
  @override Future<void> setUpdateChannel(String value) async { _updateChannel = value; }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://example.com'));
  });

  // Helper to pump the widget
  Future<void> pumpAboutScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => MockSettingsProvider(), 
          ),
        ],
        child: const MaterialApp(
          home: AboutScreen(),
        ),
      ),
    );
  }

  testWidgets('Check for Updates button should be visible and clickable', (WidgetTester tester) async {
    await pumpAboutScreen(tester);
    await tester.pumpAndSettle();

    // Verify "About" title
    expect(find.text('关于'), findsOneWidget);

    // Find the update button (assuming it's a list tile or button with "检查更新" text)
    final updateButton = find.text('检查更新');
    expect(updateButton, findsOneWidget);
    
    // Tap it
    await tester.tap(updateButton);
    await tester.pump();
  });

  testWidgets('开放源代码许可 tile is present and navigates to OpenSourceLicensesScreen',
      (WidgetTester tester) async {
    await pumpAboutScreen(tester);
    await tester.pumpAndSettle();

    // The tile should be visible
    expect(find.text('开放源代码许可'), findsOneWidget);

    // Tap the tile to navigate
    await tester.tap(find.text('开放源代码许可'));
    await tester.pumpAndSettle();

    // OpenSourceLicensesScreen should be pushed
    expect(find.byType(OpenSourceLicensesScreen), findsOneWidget);
  });
}
