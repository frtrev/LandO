import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screens/map_screen.dart';
import 'services/property_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/licenses/qwen-apache-2.0.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'Qwen 3.5 (Qwen team; GGUF quantization by Unsloth)',
    ], text);
  });
  runApp(const LandOApp());
}

class LandOApp extends StatefulWidget {
  const LandOApp({super.key});
  @override
  State<LandOApp> createState() => _LandOAppState();
}

class _LandOAppState extends State<LandOApp> {
  late final Future<({PropertyRepository repository, bool configured})>
  startup = initialize();
  Future<({PropertyRepository repository, bool configured})>
  initialize() async {
    final configured =
        await const MethodChannel(
          'lando/config',
        ).invokeMethod<bool>('mapsConfigured') ??
        false;
    return (
      repository: await PropertyRepository.open(),
      configured: configured,
    );
  }

  ThemeMode mode = ThemeMode.system;
  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff197a59),
      brightness: brightness,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LandO',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: FutureBuilder<({PropertyRepository repository, bool configured})>(
      future: startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not initialize LandO. Restart the app to retry.\n${snapshot.error}',
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.data!.configured) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 64),
                      SizedBox(height: 20),
                      Text(
                        'LandO',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Google Maps setup required',
                        style: TextStyle(fontSize: 20),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Configure this build with a Google Maps SDK key using the project README, then rebuild LandO.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return MapScreen(
          repository: snapshot.data!.repository,
          themeMode: mode,
          onTheme: (value) => setState(() => mode = value),
        );
      },
    ),
  );
}
