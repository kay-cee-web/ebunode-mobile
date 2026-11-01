import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Ebunode mobile shell: the customer's published Ebunode app, as a native Android / iOS app.
///
/// Everything app-specific comes in at build time from Codemagic (--dart-define), so one codebase
/// builds every customer's app:
///   APP_URL          the published app (https://glow-salon.ebunode.app or their custom domain)
///   APP_NAME         shown in the app bar and the offline screen
///   APPBAR_ENABLED   "true" shows a native app bar with the app's name
///   APPBAR_COLOR     #RRGGBB, app bar and status bar colour
///   SPLASH_TIMEOUT   seconds the splash may stay up at most while the first page loads
class AppConfig {
  static const url = String.fromEnvironment('APP_URL', defaultValue: 'https://ebunode.com');
  static const name = String.fromEnvironment('APP_NAME', defaultValue: 'Ebunode App');
  static const appBarEnabled = String.fromEnvironment('APPBAR_ENABLED', defaultValue: 'false') == 'true';
  static const appBarColor = String.fromEnvironment('APPBAR_COLOR', defaultValue: '#5046E5');
  static const splashTimeout = int.fromEnvironment('SPLASH_TIMEOUT', defaultValue: 3);

  static Color get color {
    final hex = appBarColor.replaceAll('#', '');
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return Color(value ?? 0xFF5046E5);
  }

  /// The app's own host, and its subdomains, stay inside the app. Everything else opens outside.
  static String get host => Uri.parse(url).host;
}

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  runApp(const EbunodeApp());
}

class EbunodeApp extends StatelessWidget {
  const EbunodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: AppConfig.color, useMaterial3: true),
      home: const WebShell(),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;
  bool _splashGone = false;
  String _title = AppConfig.name;

  @override
  void initState() {
    super.initState();

    // Never keep people staring at the splash if the network is slow
    Timer(Duration(seconds: AppConfig.splashTimeout.clamp(1, 10)), _removeSplash);

    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
            ? WebKitWebViewControllerCreationParams(
                allowsInlineMediaPlayback: true,
                mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
              )
            : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() => _failed = false),
          onPageFinished: (_) async {
            _removeSplash();
            final title = await _controller.getTitle();
            if (mounted && AppConfig.appBarEnabled && title != null && title.trim().isNotEmpty) {
              setState(() => _title = title.trim());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _removeSplash();
              setState(() => _failed = true);
            }
          },
          onNavigationRequest: _onNavigation,
        ),
      );

    final platform = controller.platform;

    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnShowFileSelector(_pickFiles);
    }

    if (platform is WebKitWebViewController) {
      platform.setAllowsBackForwardNavigationGestures(true);
    }

    controller.loadRequest(Uri.parse(AppConfig.url));
    _controller = controller;
  }

  void _removeSplash() {
    if (!_splashGone) {
      _splashGone = true;
      FlutterNativeSplash.remove();
    }
  }

  /// The app and its subdomains load inside; other sites, mail, phone, maps, stores open outside.
  Future<NavigationDecision> _onNavigation(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);

    if (uri == null) {
      return NavigationDecision.prevent;
    }

    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    final internal = isWeb && (uri.host == AppConfig.host || uri.host.endsWith('.${AppConfig.host}'));

    // Sign-in and payment pages (Google, Stripe…) open inside too, so their redirects come back
    const inAppHosts = ['accounts.google.com', 'checkout.stripe.com', 'js.stripe.com', 'hooks.stripe.com', 'www.paypal.com'];

    if (internal || (isWeb && inAppHosts.contains(uri.host)) || uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return NavigationDecision.navigate;
    }

    if (!request.isMainFrame && isWeb) {
      return NavigationDecision.navigate; // embedded content (maps, videos)
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);

    return NavigationDecision.prevent;
  }

  /// Android has no built-in picker for <input type="file">.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final accept = params.acceptTypes.join(',').toLowerCase();
    final type = accept.contains('image') && !accept.contains('video')
        ? FileType.image
        : (accept.contains('video') && !accept.contains('image') ? FileType.video : FileType.any);

    try {
      final files = await FilePicker.pickFiles(type: type);

      if (params.mode != FileSelectorMode.openMultiple && files.length > 1) {
        return [files.first.uri.toString()];
      }

      return files.map((f) => f.uri.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _retry() async {
    setState(() => _failed = false);
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.estimateBrightnessForColor(AppConfig.color) == Brightness.dark;

    final page = Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_progress < 100 && !_failed)
          LinearProgressIndicator(
            value: _progress / 100,
            minHeight: 2,
            color: AppConfig.color,
            backgroundColor: Colors.transparent,
          ),
        if (_failed) _OfflineView(onRetry: _retry),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppConfig.appBarEnabled
            ? (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: AppConfig.color)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.white),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppConfig.appBarEnabled
              ? AppBar(
                  backgroundColor: AppConfig.color,
                  foregroundColor: dark ? Colors.white : Colors.black,
                  title: Text(_title, overflow: TextOverflow.ellipsis),
                  actions: [
                    IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reload', onPressed: _retry),
                  ],
                )
              : null,
          body: SafeArea(top: !AppConfig.appBarEnabled, child: page),
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: AppConfig.color),
          const SizedBox(height: 16),
          const Text("You're offline", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            "${AppConfig.name} couldn't load. Check your connection and try again.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConfig.color),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
