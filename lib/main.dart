import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/scan_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const BillComplianceScannerApp());
}

class BillComplianceScannerApp extends StatelessWidget {
  const BillComplianceScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Bill Compliance Scanner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const ScanScreen(),
      ),
    );
  }
}
