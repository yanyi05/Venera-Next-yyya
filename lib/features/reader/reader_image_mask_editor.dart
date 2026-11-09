import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ReaderImageMaskEdit {
  const ReaderImageMaskEdit(this.rectangles, this.color);
  final List<Rect> rectangles;
  final Color color;
}

class ReaderImageMaskEditor extends StatefulWidget {
  const ReaderImageMaskEditor({
    super.key,
    required this.bytes,
    required this.initial,
    required this.initialColor,
  });
  final Uint8List bytes;
  final List<Rect> initial;
  final Color initialColor;

  @override
  State<ReaderImageMaskEditor> createState() => _ReaderImageMaskEditorState();
}

class _ReaderImageMaskEditorState extends State<ReaderImageMaskEditor> {
  ui.Image? _image;
  late final List<Rect> _rectangles = List.of(widget.initial);
  late Color _maskColor = widget.initialColor;
  Rect? _drag;
  Offset? _start;
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

  Offset? _normalized(Offset point) {
    if (!_imageRect.contains(point)) return null;
    return Offset(
      ((point.dx - _imageRect.left) / _imageRect.width)
          .clamp(0.0, 1.0)
          .toDouble(),
      ((point.dy - _imageRect.top) / _imageRect.height)
          .clamp(0.0, 1.0)
          .toDouble(),
    );
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
              title: const Text('遮挡区域'),
              subtitle: const Text('拖动绘制遮挡区域，底部调色按钮可切换黑/白；原图不会修改。'),
              leading: IconButton(
                tooltip: '取消',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              trailing: TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  ReaderImageMaskEdit(List<Rect>.of(_rectangles), _maskColor),
                ),
                child: const Text('保存'),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
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
                      final point = _normalized(details.localPosition);
                      if (point != null) {
                        setState(() {
                          _start = point;
                          _drag = Rect.fromPoints(point, point);
                        });
                      }
                    },
                    onPanUpdate: (details) {
                      final start = _start;
                      final point = _normalized(details.localPosition);
                      if (start != null && point != null) {
                        setState(() => _drag = Rect.fromPoints(start, point));
                      }
                    },
                    onPanEnd: (_) {
                      final drag = _drag;
                      if (drag != null &&
                          drag.width > .005 &&
                          drag.height > .005) {
                        setState(() => _rectangles.add(drag));
                      }
                      setState(() {
                        _start = null;
                        _drag = null;
                      });
                    },
                    child: CustomPaint(
                      painter: _MaskPreviewPainter(
                        image: image,
                        imageRect: _imageRect,
                        rectangles: [..._rectangles, ?_drag],
                        color: _maskColor,
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
                  Text('${_rectangles.length} 个区域'),
                  IconButton(
                    tooltip: _maskColor == Colors.white ? '白色遮挡' : '黑色遮挡',
                    onPressed: () => setState(
                      () => _maskColor = _maskColor == Colors.white
                          ? Colors.black
                          : Colors.white,
                    ),
                    icon: Icon(Icons.palette, color: _maskColor),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _rectangles.isEmpty
                        ? null
                        : () => setState(_rectangles.clear),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除全部'),
                  ),
                  TextButton.icon(
                    onPressed: _rectangles.isEmpty
                        ? null
                        : () => setState(_rectangles.removeLast),
                    icon: const Icon(Icons.undo),
                    label: const Text('撤销'),
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

class _MaskPreviewPainter extends CustomPainter {
  const _MaskPreviewPainter({
    required this.image,
    required this.imageRect,
    required this.rectangles,
    required this.color,
  });
  final ui.Image image;
  final Rect imageRect;
  final List<Rect> rectangles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final paint = Paint()..color = color;
    for (final rect in rectangles) {
      canvas.drawRect(
        Rect.fromLTRB(
          imageRect.left + rect.left * imageRect.width,
          imageRect.top + rect.top * imageRect.height,
          imageRect.left + rect.right * imageRect.width,
          imageRect.top + rect.bottom * imageRect.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPreviewPainter old) =>
      old.image != image ||
      old.imageRect != imageRect ||
      old.rectangles != rectangles ||
      old.color != color;
}
