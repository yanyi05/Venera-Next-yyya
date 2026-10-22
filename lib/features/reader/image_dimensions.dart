import 'package:flutter/material.dart';
import 'auto_reading.dart';
import 'package:venera_next/foundation/image_provider/base_image_provider.dart';
import 'package:venera_next/foundation/translations.dart';

Size decodedOriginalSize(ImageStream? stream, ImageInfo info) =>
    (stream?.completer is OriginalImageSize
        ? (stream!.completer as OriginalImageSize).originalImageSize
        : null) ??
    Size(info.image.width.toDouble(), info.image.height.toDouble());

/// Observes the same provider used by PhotoView, sharing its load and decode.
class ReaderImageDimensions extends StatefulWidget {
  const ReaderImageDimensions({
    super.key,
    required this.image,
    this.child,
    this.builder,
    this.sizeBuilder,
    this.showDimensions = true,
    this.onLoadState,
  }) : assert(
         (child == null ? 0 : 1) +
                 (builder == null ? 0 : 1) +
                 (sizeBuilder == null ? 0 : 1) ==
             1,
       );
  final ImageProvider image;
  final bool showDimensions;
  final ValueChanged<AutoReadingImageState>? onLoadState;
  final Widget? child;
  final Widget Function(VoidCallback reload)? builder;
  final Widget Function(Size? size, VoidCallback reload)? sizeBuilder;

  @override
  State<ReaderImageDimensions> createState() => _ReaderImageDimensionsState();
}

class _ReaderImageDimensionsState extends State<ReaderImageDimensions> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ReaderImageDimensions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _detach();
    _size = null;
    _stream = stream;
    widget.onLoadState?.call(AutoReadingImageState.loading);
    _listener = ImageStreamListener(
      (info, synchronous) {
        try {
          if (!mounted || !identical(_stream, stream)) return;
          widget.onLoadState?.call(AutoReadingImageState.ready);
          final size = decodedOriginalSize(stream, info);
          if (_size == size || !mounted) return;
          if (synchronous) {
            _size = size;
          } else {
            setState(() => _size = size);
          }
        } finally {
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted || !identical(_stream, stream)) return;
        widget.onLoadState?.call(AutoReadingImageState.failed);
        if (_size != null) setState(() => _size = null);
      },
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
  }

  void _reload() {
    setState(() {
      _detach();
      _resolve();
    });
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageDimensionsOverlay(
    size: widget.showDimensions ? _size : null,
    child:
        widget.sizeBuilder?.call(_size, _reload) ??
        widget.builder?.call(_reload) ??
        widget.child!,
  );
}

class ImageDimensionsOverlay extends StatelessWidget {
  const ImageDimensionsOverlay({
    super.key,
    required this.size,
    required this.child,
  });
  final Size? size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = this.size;
    if (size == null) return child;
    final width = size.width.round();
    final height = size.height.round();
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          bottom: 4,
          right: 4,
          left: 4,
          child: Align(
            alignment: Alignment.bottomRight,
            child: IgnorePointer(
              child: Semantics(
                label: 'Image dimensions: @width × @height pixels'.tlParams({
                  'width': width,
                  'height': height,
                }),
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.9,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$width × $height',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
