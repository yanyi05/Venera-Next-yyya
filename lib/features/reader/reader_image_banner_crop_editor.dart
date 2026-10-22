import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ReaderImageBannerCropEdit {
  const ReaderImageBannerCropEdit(this.band);
  final Rect? band;
}

class ReaderImageBannerCropEditor extends StatefulWidget {
  const ReaderImageBannerCropEditor({
    super.key,
    required this.bytes,
    required this.initialBand,
    required this.detectedBand,
  });

  final Uint8List bytes;
  final Rect? initialBand;
  final Rect? detectedBand;

  @override
  State<ReaderImageBannerCropEditor> createState() =>
      _ReaderImageBannerCropEditorState();
}

class _ReaderImageBannerCropEditorState
    extends State<ReaderImageBannerCropEditor> {
  ui.Image? _image;
  late Rect? _band = widget.initialBand;
  Rect? _dragBand;
  double? _dragStart;
  Rect _imageRect = Rect.zero;
  Object? _decodeError;

  @override
  void initState() {
    super.initState();
    _decodePreview();
  }

  Future<void> _decodePreview() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: 1600,
        targetHeight: 2400,
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _image = frame.image);
      } else {
        frame.image.dispose();
      }
    } catch (error) {
      if (mounted) setState(() => _decodeError = error);
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double? _normalizedY(double y) {
    if (!_imageRect.contains(Offset(_imageRect.center.dx, y))) return null;
    return ((y - _imageRect.top) / _imageRect.height).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      if (_decodeError case final error?) {
        return Dialog.fullscreen(
          child: Center(child: Text('Unable to open image: $error')),
        );
      }
      return const Dialog.fullscreen(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text('包子横幅裁切预览'),
              subtitle: Text(
                widget.detectedBand == null
                    ? '未自动识别到横幅。可在图片上拖动选择要移除的横向区域。'
                    : '已标出自动识别范围。拖动图片可重新选择；确认后移除整条横幅并拼接上下画面。',
              ),
              leading: IconButton(
                tooltip: '取消',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              trailing: TextButton(
                onPressed: _band == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        ReaderImageBannerCropEdit(_band),
                      ),
                child: const Text('应用裁切'),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  final fitted = applyBoxFit(
                    BoxFit.contain,
                    Size(image.width.toDouble(), image.height.toDouble()),
                    size,
                  );
                  _imageRect = Alignment.center.inscribe(
                    fitted.destination,
                    Offset.zero & size,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      final y = _normalizedY(details.localPosition.dy);
                      if (y == null) return;
                      setState(() {
                        _dragStart = y;
                        _dragBand = Rect.fromLTRB(0, y, 1, y);
                      });
                    },
                    onPanUpdate: (details) {
                      final start = _dragStart;
                      final y = _normalizedY(details.localPosition.dy);
                      if (start == null || y == null) return;
                      setState(() {
                        _dragBand = Rect.fromLTRB(
                          0,
                          start < y ? start : y,
                          1,
                          start < y ? y : start,
                        );
                      });
                    },
                    onPanEnd: (_) {
                      final drag = _dragBand;
                      if (drag != null && drag.height > .005) {
                        setState(() => _band = drag);
                      }
                      setState(() {
                        _dragStart = null;
                        _dragBand = null;
                      });
                    },
                    child: CustomPaint(
                      painter: _BannerCropPreviewPainter(
                        image: image,
                        imageRect: _imageRect,
                        band: _dragBand ?? _band,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    _band == null
                        ? '未选择裁切区域'
                        : '裁切范围：${(_band!.top * 100).round()}%–${(_band!.bottom * 100).round()}%',
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: widget.detectedBand == null
                        ? null
                        : () => setState(() => _band = widget.detectedBand),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('恢复自动识别'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerCropPreviewPainter extends CustomPainter {
  const _BannerCropPreviewPainter({
    required this.image,
    required this.imageRect,
    required this.band,
  });

  final ui.Image image;
  final Rect imageRect;
  final Rect? band;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final selected = band;
    if (selected == null) return;
    final top = imageRect.top + selected.top * imageRect.height;
    final bottom = imageRect.top + selected.bottom * imageRect.height;
    final rect = Rect.fromLTRB(imageRect.left, top, imageRect.right, bottom);
    canvas.drawRect(rect, Paint()..color = const Color(0x6680CBC4));
    final border = Paint()
      ..color = const Color(0xFF80CBC4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, border);
    canvas.drawLine(Offset(rect.left, top), Offset(rect.right, top), border);
    canvas.drawLine(
      Offset(rect.left, bottom),
      Offset(rect.right, bottom),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _BannerCropPreviewPainter old) =>
      old.image != image || old.imageRect != imageRect || old.band != band;
}
