import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/demo_fixtures.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_button.dart';
import 'history_screen.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _cameraError;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError =
            'No camera found on this device. Use "Load from gallery" or Demo Mode.');
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      final future = controller.initialize();
      setState(() {
        _controller = controller;
        _initFuture = future;
        _cameraError = null;
      });
      await future;
      if (mounted) setState(() {});
    } catch (e) {
      // A camera failure must not dead-end the demo: gallery and demo mode
      // both remain available.
      setState(() => _cameraError =
          'Camera unavailable ($e). Use "Load from gallery" or Demo Mode.');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_capturing) return;

    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      await _runPipeline(() =>
          context.read<AppState>().processImage(file.path, source: 'camera'));
    } catch (e) {
      if (mounted) _showError('Could not take the photo: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null || !mounted) return;
      await _runPipeline(() =>
          context.read<AppState>().processImage(image.path, source: 'gallery'));
    } catch (e) {
      if (mounted) _showError('Could not open the gallery: $e');
    }
  }

  /// Runs a pipeline action behind a modal progress indicator, then routes to
  /// either the result screen or the retake prompt.
  Future<void> _runPipeline(Future<void> Function() action) async {
    final state = context.read<AppState>();
    _showProcessingDialog();

    await action();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss progress

    if (!mounted) return;
    if (state.status == ScanStatus.unreadable ||
        state.status == ScanStatus.error) {
      _showRetakeSheet(state.errorMessage ??
          "Couldn't read the bill clearly — retake photo.");
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
  }

  void _showProcessingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 18),
                Text('Reading the bill…',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('On-device — nothing leaves your phone',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRetakeSheet(String message) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.warningSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.image_not_supported_rounded,
                      color: AppColors.warning),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Couldn't read the bill",
                      style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(message,
                style: const TextStyle(
                    fontSize: 16, height: 1.4, color: AppColors.textPrimary)),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Retake photo'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                _pickFromGallery();
              },
              child: const Text('Load from gallery instead'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDemoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Demo Mode',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Runs the rule engine on a known bill, bypassing the camera.',
                style:
                    TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              ...DemoFixtures.all().map(
                (fixture) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _runDemo(fixture);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fixture.label,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(fixture.description,
                              style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runDemo(DemoFixture fixture) async {
    final state = context.read<AppState>();
    // Fixtures with receipt text go through the real parser, so demo mode
    // exercises the same code path a printed scan would.
    if (fixture.receiptText.trim().isNotEmpty) {
      await state.processText(fixture.receiptText, source: 'demo');
    } else {
      await state.loadBill(fixture.bill);
    }
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ResultScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Bill Compliance Scanner'),
        actions: [
          IconButton(
            tooltip: 'Scan history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Demo mode',
            icon: const Icon(Icons.science_rounded),
            onPressed: _openDemoSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildPreview()),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white54, size: 58),
            const SizedBox(height: 18),
            Text(
              _cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 22),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: _initCamera,
              child: const Text('Try camera again'),
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null || _initFuture == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1080,
                height: controller.value.previewSize?.width ?? 1920,
                child: CameraPreview(controller),
              ),
            ),
            const FramingOverlay(
                hint: 'Fit the whole bill inside the frame'),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SecondaryAction(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              onPressed: _pickFromGallery,
            ),
            ScanButton(
              busy: _capturing,
              onPressed: _cameraError == null ? _capture : null,
            ),
            _SecondaryAction(
              icon: Icons.science_rounded,
              label: 'Demo',
              onPressed: _openDemoSheet,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 27),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
