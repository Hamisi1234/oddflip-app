import 'package:flutter/material.dart';

class AppLoadingIndicator extends StatefulWidget {
  const AppLoadingIndicator({
    this.label = 'Loading',
    this.compact = false,
    this.color,
    super.key,
  });

  final String label;
  final bool compact;
  final Color? color;

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.primary;
    if (widget.compact) {
      return Semantics(
        label: widget.label,
        liveRegion: true,
        child: RotationTransition(
          turns: _controller,
          child: Icon(Icons.sports_soccer, color: color, size: 20),
        ),
      );
    }

    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns: _controller,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(alpha: .3),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  ScaleTransition(
                    scale: Tween<double>(begin: .82, end: 1.08).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Icon(
                      Icons.sports_soccer,
                      color: color,
                      size: 25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 4,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _LoadingTrackPainter(
                      progress: _controller.value,
                      color: color,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingTrackPainter extends CustomPainter {
  const _LoadingTrackPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: .12),
    );
    final segmentWidth = size.width * .32;
    final left = (size.width + segmentWidth) * progress - segmentWidth;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, segmentWidth, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingTrackPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
