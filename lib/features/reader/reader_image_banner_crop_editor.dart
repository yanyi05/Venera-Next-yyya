import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:venera_next/foundation/image_crop_bands.dart';

class ReaderImageBannerCropEdit {
  const ReaderImageBannerCropEdit(this.bands);
  // null: use source; []: explicitly restore original.
  final List<Rect>? bands;
}

class ReaderImageBannerCropEditor extends StatefulWidget {
  const ReaderImageBannerCropEditor({
    super.key,
    required this.bytes,
    required this.initialBands,
  });
  final Uint8List bytes;
  final List<Rect>? initialBands;
  @override
  State<ReaderImageBannerCropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<ReaderImageBannerCropEditor> {
  ui.Image? _image;
  Object? _error;
  late List<Rect> _bands = List.of(widget.initialBands ?? []);
  Rect? _drag;
  double? _start;
  Rect _bounds = Rect.zero;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    ui.Codec? codec;
    try {
      // Width-only target preserves the original aspect ratio.
      codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: 1200,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double _y(Offset p) =>
      ((p.dy - _bounds.top) / _bounds.height).clamp(0.0, 1.0);

  void _finishDrag() {
    final drag = _drag;
    if (drag != null && drag.height >= .005) {
      try {
        final merged = normalizeImageCropBands([
          for (final b in [..._bands, drag]) {'top': b.top, 'bottom': b.bottom},
        ]);
        _bands = [for (final b in merged) Rect.fromLTRB(0, b.top, 1, b.bottom)];
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('裁切总高度不能超过原图的 30%，最多 32 个区域')),
        );
      }
    }
    setState(() {
      _drag = null;
      _start = null;
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('图片裁切'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              ReaderImageBannerCropEdit(List.of(_bands)),
            ),
            child: const Text('应用'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('在原图上拖动可添加多个横向区域。最多移除总高度的 30%。手动设置优先于源处理。'),
            ),
            Expanded(
              child: _image == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Text('无法打开原图：$_error'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final image = _image!;
                        final rows = retainedImageRows([
                          for (final b in _bands)
                            {'top': b.top, 'bottom': b.bottom},
                        ], image.height);
                        final previewHeight = rows.fold<int>(
                          0,
                          (sum, r) => sum + r.bottom - r.top,
                        );
                        final size = constraints.biggest;
                        final fitted = applyBoxFit(
                          BoxFit.contain,
                          Size(
                            image.width.toDouble(),
                            (_preview ? previewHeight : image.height)
                                .toDouble(),
                          ),
                          size,
                        );
                        _bounds = Alignment.center.inscribe(
                          fitted.destination,
                          Offset.zero & size,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _preview
                              ? null
                              : (d) {
                                  if (!_bounds.contains(d.localPosition)) {
                                    return;
                                  }
                                  setState(() {
                                    _start = _y(d.localPosition);
                                  });
                                },
                          onPanUpdate: _preview
                              ? null
                              : (d) {
                                  final start = _start;
                                  if (start == null) return;
                                  final y = _y(d.localPosition);
                                  setState(
                                    () => _drag = Rect.fromLTRB(
                                      0,
                                      start < y ? start : y,
                                      1,
                                      start < y ? y : start,
                                    ),
                                  );
                                },
                          onPanEnd: _preview ? null : (_) => _finishDrag(),
                          onPanCancel: () => setState(() {
                            _start = null;
                            _drag = null;
                          }),
                          child: CustomPaint(
                            painter: _CropPainter(image, _bounds, [
                              ..._bands,
                              ?_drag,
                            ], _preview ? rows : null),
                            child: const SizedBox.expand(),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _preview = !_preview),
                    icon: const Icon(Icons.compare),
                    label: Text(_preview ? '返回原图' : '裁切预览'),
                  ),
                  TextButton(
                    onPressed: _bands.isEmpty
                        ? null
                        : () => setState(() => _bands.removeLast()),
                    child: const Text('删除末个区域'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _bands.clear();
                      _preview = false;
                    }),
                    child: const Text('清空选区'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const ReaderImageBannerCropEdit([]),
                    ),
                    child: const Text('恢复原图'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const ReaderImageBannerCropEdit(null),
                    ),
                    child: const Text('使用源处理'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.image, this.bounds, this.bands, this.rows);
  final ui.Image image;
  final Rect bounds;
  final List<Rect> bands;
  final List<({int top, int bottom})>? rows;
  @override
  void paint(Canvas canvas, Size size) {
    final retained = rows;
    if (retained != null) {
      final height = retained.fold<int>(0, (sum, r) => sum + r.bottom - r.top);
      var y = 0;
      for (final row in retained) {
        final h = row.bottom - row.top;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            0,
            row.top.toDouble(),
            image.width.toDouble(),
            h.toDouble(),
          ),
          Rect.fromLTWH(
            bounds.left,
            bounds.top + y / height * bounds.height,
            bounds.width,
            h / height * bounds.height,
          ),
          Paint(),
        );
        y += h;
      }
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        bounds,
        Paint(),
      );
      for (final b in bands) {
        canvas.drawRect(
          Rect.fromLTRB(
            bounds.left,
            bounds.top + b.top * bounds.height,
            bounds.right,
            bounds.top + b.bottom * bounds.height,
          ),
          Paint()..color = const Color(0x6680CBC4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
