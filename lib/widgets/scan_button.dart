import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The camera shutter. Large and unmissable — it is the one control the
/// demo depends on, pressed by someone who has not used the app before.
class ScanButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;

  const ScanButton({super.key, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture bill',
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.2),
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.document_scanner_rounded,
                      color: AppColors.primary,
                      size: 30,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Darkens everything outside a bill-shaped window and draws corner marks,
/// so the user knows where to put the receipt.
class FramingOverlay extends StatelessWidget {
  final String hint;

  const FramingOverlay({super.key, required this.hint});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Receipts are tall and narrow; match that shape.
        final width = constraints.maxWidth * 0.82;
        final height = constraints.maxHeight * 0.62;

        return Stack(
          children: [
            // Dimmed surround with a clear window cut out of it.
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: CustomPaint(painter: _CornerPainter()),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: (constraints.maxHeight - height) / 2 - 48,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    hint,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = 30.0;

    // Top-left
    canvas.drawLine(const Offset(0, arm), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(arm, 0), paint);
    // Top-right
    canvas.drawLine(Offset(size.width - arm, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height - arm), Offset(0, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(arm, size.height), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height - arm),
        Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width - arm, size.height),
        Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
