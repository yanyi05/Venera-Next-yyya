import 'dart:ui' as ui;
import 'dart:async';
import 'display_image_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:venera_next/features/reader/reader_tap_scope.dart';
import 'package:venera_next/features/reader/image_position.dart';
import 'package:venera_next/features/reader/reader_image_masks.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';
import 'image_dimensions.dart';
import 'auto_reading.dart';

class ComicImage extends StatefulWidget {
  /// Modified from flutter Image
  ComicImage({
    required ImageProvider image,
    super.key,
    double scale = 1.0,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
    this.isAntiAlias = false,
    this.splitWideImage = false,
    this.splitWideImageInvert = false,
    this.showImageDimensions = false,
    this.maskAddress,
    Map<String, String>? headers,
    int? cacheWidth,
    int? cacheHeight,
    this.onInit,
    this.onDispose,
    this.onRetry,
  }) : image = ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, image),
       assert(cacheWidth == null || cacheWidth > 0),
       assert(cacheHeight == null || cacheHeight > 0);

  final ImageProvider image;

  final String? semanticLabel;

  final bool excludeFromSemantics;

  final double? width;

  final double? height;

  final bool gaplessPlayback;

  final bool matchTextDirection;

  final Rect? centerSlice;

  final ImageRepeat repeat;

  final AlignmentGeometry alignment;

  final BoxFit? fit;

  final BlendMode? colorBlendMode;

  final FilterQuality filterQuality;

  final Animation<double>? opacity;

  final Color? color;

  final bool isAntiAlias;

  final bool splitWideImage;

  final bool splitWideImageInvert;
  final bool showImageDimensions;
  final ReaderImageAddress? maskAddress;

  final void Function(State<ComicImage> state)? onInit;

  final void Function(State<ComicImage> state)? onDispose;
  final VoidCallback? onRetry;

  static void clear() => ComicImageState.clear();

  @override
  State<ComicImage> createState() => ComicImageState();
}

@visibleForTesting
bool shouldSplitWideImage(Size imageSize) => imageSize.width > imageSize.height;

@visibleForTesting
Size splitWideImageDisplaySize(Size imageSize) {
  if (!shouldSplitWideImage(imageSize)) {
    return imageSize;
  }
  return Size(imageSize.width / 2, imageSize.height * 2);
}

@visibleForTesting
List<Rect> splitWideImageSourceRects(Size imageSize, {required bool invert}) {
  return [
    for (final slice in splitWideImageSlices(invert: invert))
      Rect.fromLTWH(
        imageSize.width * slice.sourceLeft,
        0,
        imageSize.width * slice.sourceWidth,
        imageSize.height,
      ),
  ];
}

class ComicImageState extends State<ComicImage> with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  late bool _invertColors;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  late DisposableBuildContext<State<ComicImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;

  AutoReadingImageState get autoReadingImageState => _lastException != null
      ? AutoReadingImageState.failed
      : _imageInfo != null && _frameNumber != null
      ? AutoReadingImageState.ready
      : AutoReadingImageState.loading;

  bool get readyForAutoReading =>
      autoReadingImageState == AutoReadingImageState.ready;

  bool get visibleInReader {
    if (!mounted) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visible = bounds.intersect(screen);
    return visible.width > 1 && visible.height > 1;
  }

  static final _cache = <Object, Size>{};
  Object get _sizeKey {
    final provider = widget.image;
    return provider is ReaderDisplayImageProvider ? provider.image : provider;
  }

  Timer? _chunkTimer;
  ImageChunkEvent? _pendingChunk;
  void _clearChunk() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    _pendingChunk = null;
  }

  void _rememberSize(Size size) {
    _cache.remove(_sizeKey);
    _cache[_sizeKey] = size;
    while (_cache.length > 512) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void clear() => _cache.clear();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAwareContext = DisposableBuildContext<State<ComicImage>>(this);
    widget.onInit?.call(this);
  }

  @override
  void dispose() {
    assert(_imageStream != null);
    _clearChunk();
    WidgetsBinding.instance.removeObserver(this);
    _stopListeningToStream();
    _completerHandle?.dispose();
    _scrollAwareContext.dispose();
    _replaceImage(info: null);
    widget.onDispose?.call(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _updateInvertColors();
    _resolveImage();

    if (TickerMode.valuesOf(context).enabled) {
      _listenToStream();
    } else {
      _stopListeningToStream(keepStreamAlive: true);
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(ComicImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _resolveImage();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    setState(() {
      _updateInvertColors();
    });
  }

  @override
  void reassemble() {
    _resolveImage(); // in case the image cache was flushed
    super.reassemble();
  }

  bool containsPoint(Offset point) {
    if (!mounted) {
      return false;
    }
    var renderBox = context.findRenderObject() as RenderBox;
    var localPoint = renderBox.globalToLocal(point);
    return renderBox.paintBounds.contains(localPoint);
  }

  void _updateInvertColors() {
    _invertColors =
        MediaQuery.maybeInvertColorsOf(context) ??
        SemanticsBinding.instance.accessibilityFeatures.invertColors;
  }

  void _resolveImage() {
    final ScrollAwareImageProvider provider = ScrollAwareImageProvider<Object>(
      context: _scrollAwareContext,
      imageProvider: widget.image,
    );
    final ImageStream newStream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    _updateSourceStream(newStream);
  }

  ImageStreamListener? _imageStreamListener;

  ImageStreamListener _getListener({bool recreateListener = false}) {
    if (_imageStreamListener == null || recreateListener) {
      _lastException = null;
      _imageStreamListener = ImageStreamListener(
        _handleImageFrame,
        onChunk: _handleImageChunk,
        onError: (Object error, StackTrace? stackTrace) {
          _clearChunk();
          setState(() {
            _lastException = error;
          });
        },
      );
    }
    return _imageStreamListener!;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    _clearChunk();
    setState(() {
      _replaceImage(info: imageInfo);
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = _wasSynchronouslyLoaded | synchronousCall;
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    _pendingChunk = event;
    _chunkTimer ??= Timer(const Duration(milliseconds: 120), () {
      _chunkTimer = null;
      if (!mounted || _pendingChunk == null) return;
      setState(() {
        _loadingProgress = _pendingChunk;
        _pendingChunk = null;
        _lastException = null;
      });
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final ImageInfo? oldImageInfo = _imageInfo;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => oldImageInfo?.dispose(),
    );
    _imageInfo = info;
  }

  // Updates _imageStream to newStream, and moves the stream listener
  // registration from the old stream to the new stream (if a listener was
  // registered).
  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) {
      return;
    }

    _clearChunk();
    if (_isListeningToStream) {
      _imageStream!.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      setState(() {
        _replaceImage(info: null);
      });
    }

    setState(() {
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = null;
      _wasSynchronouslyLoaded = false;
    });

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream) {
      return;
    }

    _imageStream!.addListener(_getListener());
    _completerHandle?.dispose();
    _completerHandle = null;

    _isListeningToStream = true;
  }

  /// Stops listening to the image stream, if this state object has attached a
  /// listener.
  ///
  /// If the listener from this state is the last listener on the stream, the
  /// stream will be disposed. To keep the stream alive, set `keepStreamAlive`
  /// to true, which create [ImageStreamCompleterHandle] to keep the completer
  /// alive and is compatible with the [TickerMode] being off.
  void _stopListeningToStream({bool keepStreamAlive = false}) {
    if (!_isListeningToStream) {
      return;
    }

    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }

    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastException != null) {
      // display error and retry button on screen
      return SizedBox(
        height: widget.height == null ? 300 : null,
        width: widget.width == null ? 300 : null,
        child: Center(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(_lastException.toString(), maxLines: 3),
                  ),
                ),
                const SizedBox(height: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Listener(
                    onPointerDown: (details) {
                      ReaderTapScope.maybeOf(context)?.ignoreNextTap();
                      setState(() {
                        _loadingProgress = null;
                        _lastException = null;
                      });
                      _resolveImage();
                      widget.onRetry?.call();
                    },
                    child: SizedBox(
                      width: 84,
                      height: 36,
                      child: Center(
                        child: Text(
                          "Retry".tl,
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constrains) {
        var width = widget.width;
        var height = widget.height;

        if (_imageInfo != null) {
          // Record the height and the width of the image
          _rememberSize(
            Size(
              _imageInfo!.image.width.toDouble(),
              _imageInfo!.image.height.toDouble(),
            ),
          );
        }

        Size? cacheSize = _cache[_sizeKey];
        // PhotoView may initially measure a custom child without finite bounds.
        // Keep its loading geometry finite until the actual aspect ratio arrives.
        final fallback =
            MediaQuery.maybeSizeOf(context) ?? const Size(300, 300);
        if (width == double.infinity && height == double.infinity) {
          final known = cacheSize == null
              ? null
              : widget.splitWideImage
              ? splitWideImageDisplaySize(cacheSize)
              : cacheSize;
          width = constrains.hasBoundedWidth
              ? constrains.maxWidth
              : known?.width ?? fallback.width;
          height = constrains.hasBoundedHeight
              ? constrains.maxHeight
              : known?.height ?? fallback.height;
        }
        if (cacheSize != null) {
          final displaySize = widget.splitWideImage
              ? splitWideImageDisplaySize(cacheSize)
              : cacheSize;
          if (width == double.infinity) {
            width = constrains.hasBoundedWidth
                ? constrains.maxWidth
                : fallback.width;
            height = width * displaySize.height / displaySize.width;
          } else if (height == double.infinity) {
            height = constrains.hasBoundedHeight
                ? constrains.maxHeight
                : fallback.height;
            width = height * displaySize.width / displaySize.height;
          }
        } else {
          if (width == double.infinity) {
            width = constrains.hasBoundedWidth
                ? constrains.maxWidth
                : fallback.width;
            height = 300;
          } else if (height == double.infinity) {
            height = constrains.hasBoundedHeight
                ? constrains.maxHeight
                : fallback.height;
            width = 300;
          }
        }

        if (_imageInfo != null) {
          final imageSize = Size(
            _imageInfo!.image.width.toDouble(),
            _imageInfo!.image.height.toDouble(),
          );
          final shouldSplit =
              widget.splitWideImage && shouldSplitWideImage(imageSize);
          // build image
          Widget result = shouldSplit
              ? _SplitWideImage(
                  image: _imageInfo!.image,
                  width: width,
                  height: height,
                  color: widget.color,
                  opacity: widget.opacity,
                  colorBlendMode: widget.colorBlendMode,
                  fit: widget.fit,
                  alignment: widget.alignment,
                  matchTextDirection: widget.matchTextDirection,
                  invertColors: _invertColors,
                  isAntiAlias: widget.isAntiAlias,
                  filterQuality: widget.filterQuality,
                  splitInvert: widget.splitWideImageInvert,
                )
              : RawImage(
                  // Do not clone the image, because RawImage is a stateless wrapper.
                  // The image will be disposed by this state object when it is not needed
                  // anymore, such as when it is unmounted or when the image stream pushes
                  // a new image.
                  image: _imageInfo?.image,
                  debugImageLabel: _imageInfo?.debugLabel,
                  width: width,
                  height: height,
                  scale: _imageInfo?.scale ?? 1.0,
                  color: widget.color,
                  opacity: widget.opacity,
                  colorBlendMode: widget.colorBlendMode,
                  fit: widget.fit,
                  alignment: widget.alignment,
                  repeat: widget.repeat,
                  centerSlice: widget.centerSlice,
                  matchTextDirection: widget.matchTextDirection,
                  invertColors: _invertColors,
                  isAntiAlias: widget.isAntiAlias,
                  filterQuality: widget.filterQuality,
                );

          if (!widget.excludeFromSemantics) {
            result = Semantics(
              container: widget.semanticLabel != null,
              image: true,
              label: widget.semanticLabel ?? '',
              child: result,
            );
          }
          final maskAddress = widget.maskAddress;
          result = SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: result),
                if (maskAddress != null)
                  AnimatedBuilder(
                    animation: ReaderImageMasks.changes,
                    builder: (context, _) {
                      final masks = ReaderImageMasks.read(maskAddress);
                      if (masks.isEmpty) return const SizedBox.shrink();
                      return IgnorePointer(
                        child: CustomPaint(
                          painter: _ReaderMaskPainter(
                            imageSize: imageSize,
                            rectangles: masks,
                            color: ReaderImageMasks.readColor(maskAddress),
                            fit: widget.fit ?? BoxFit.scaleDown,
                            alignment: widget.alignment.resolve(
                              Directionality.maybeOf(context),
                            ),
                            split: shouldSplit,
                            splitInvert: widget.splitWideImageInvert,
                            matchTextDirection: widget.matchTextDirection,
                            textDirection: Directionality.maybeOf(context),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
          return widget.showImageDimensions
              ? ImageDimensionsOverlay(
                  size: decodedOriginalSize(_imageStream, _imageInfo!),
                  child: result,
                )
              : result;
        } else {
          // build progress
          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  backgroundColor: context.colorScheme.surfaceContainer,
                  value:
                      (_loadingProgress != null &&
                          _loadingProgress!.expectedTotalBytes != null &&
                          _loadingProgress!.expectedTotalBytes! != 0)
                      ? _loadingProgress!.cumulativeBytesLoaded /
                            _loadingProgress!.expectedTotalBytes!
                      : 0,
                ),
              ),
            ),
          );
        }
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ImageStream>('stream', _imageStream));
    properties.add(DiagnosticsProperty<ImageInfo>('pixels', _imageInfo));
    properties.add(
      DiagnosticsProperty<ImageChunkEvent>('loadingProgress', _loadingProgress),
    );
    properties.add(DiagnosticsProperty<int>('frameNumber', _frameNumber));
    properties.add(
      DiagnosticsProperty<bool>(
        'wasSynchronouslyLoaded',
        _wasSynchronouslyLoaded,
      ),
    );
  }
}

class _ReaderMaskPainter extends CustomPainter {
  const _ReaderMaskPainter({
    required this.imageSize,
    required this.rectangles,
    required this.color,
    required this.fit,
    required this.alignment,
    required this.split,
    required this.splitInvert,
    required this.matchTextDirection,
    required this.textDirection,
  });
  final Size imageSize;
  final List<Rect> rectangles;
  final Color color;
  final BoxFit fit;
  final Alignment alignment;
  final bool split;
  final bool splitInvert;
  final bool matchTextDirection;
  final TextDirection? textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final displaySize = split
        ? splitWideImageDisplaySize(imageSize)
        : imageSize;
    final fitted = applyBoxFit(fit, displaySize, size);
    final destination = alignment.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final paint = Paint()..color = color;
    if (!split) {
      for (final rect in rectangles) {
        canvas.drawRect(
          Rect.fromLTRB(
            destination.left + rect.left * destination.width,
            destination.top + rect.top * destination.height,
            destination.left + rect.right * destination.width,
            destination.top + rect.bottom * destination.height,
          ),
          paint,
        );
      }
      return;
    }
    final slices = splitWideImageSlices(
      invert:
          splitInvert ^
          (matchTextDirection && textDirection == TextDirection.rtl),
    );
    for (final rect in rectangles) {
      for (final slice in slices) {
        final left = slice.sourceLeft;
        final right = left + slice.sourceWidth;
        final clippedLeft = rect.left.clamp(left, right).toDouble();
        final clippedRight = rect.right.clamp(left, right).toDouble();
        if (clippedRight <= clippedLeft) continue;
        canvas.drawRect(
          Rect.fromLTRB(
            destination.left +
                ((clippedLeft - left) / slice.sourceWidth) * destination.width,
            destination.top +
                (slice.displayTop + rect.top * slice.displayHeight) *
                    destination.height,
            destination.left +
                ((clippedRight - left) / slice.sourceWidth) * destination.width,
            destination.top +
                (slice.displayTop + rect.bottom * slice.displayHeight) *
                    destination.height,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReaderMaskPainter old) =>
      old.imageSize != imageSize ||
      old.rectangles != rectangles ||
      old.color != color ||
      old.fit != fit ||
      old.alignment != alignment ||
      old.split != split ||
      old.splitInvert != splitInvert ||
      old.matchTextDirection != matchTextDirection ||
      old.textDirection != textDirection;
}

class _SplitWideImage extends StatelessWidget {
  const _SplitWideImage({
    required this.image,
    required this.width,
    required this.height,
    required this.color,
    required this.opacity,
    required this.colorBlendMode,
    required this.fit,
    required this.alignment,
    required this.matchTextDirection,
    required this.invertColors,
    required this.isAntiAlias,
    required this.filterQuality,
    required this.splitInvert,
  });

  final ui.Image image;

  final double? width;

  final double? height;

  final Color? color;

  final Animation<double>? opacity;

  final BlendMode? colorBlendMode;

  final BoxFit? fit;

  final AlignmentGeometry alignment;

  final bool matchTextDirection;

  final bool invertColors;

  final bool isAntiAlias;

  final FilterQuality filterQuality;

  final bool splitInvert;

  @override
  Widget build(BuildContext context) {
    Widget result = CustomPaint(
      size: Size(
        width ?? image.width.toDouble() / 2,
        height ?? image.height * 2,
      ),
      painter: _SplitWideImagePainter(
        image: image,
        color: color,
        colorBlendMode: colorBlendMode,
        fit: fit,
        alignment: alignment.resolve(Directionality.maybeOf(context)),
        matchTextDirection: matchTextDirection,
        textDirection: Directionality.maybeOf(context),
        invertColors: invertColors,
        isAntiAlias: isAntiAlias,
        filterQuality: filterQuality,
        splitInvert: splitInvert,
      ),
    );
    if (opacity != null) {
      result = FadeTransition(opacity: opacity!, child: result);
    }
    return SizedBox(width: width, height: height, child: result);
  }
}

class _SplitWideImagePainter extends CustomPainter {
  const _SplitWideImagePainter({
    required this.image,
    required this.color,
    required this.colorBlendMode,
    required this.fit,
    required this.alignment,
    required this.matchTextDirection,
    required this.textDirection,
    required this.invertColors,
    required this.isAntiAlias,
    required this.filterQuality,
    required this.splitInvert,
  });

  final ui.Image image;

  final Color? color;

  final BlendMode? colorBlendMode;

  final BoxFit? fit;

  final Alignment alignment;

  final bool matchTextDirection;

  final TextDirection? textDirection;

  final bool invertColors;

  final bool isAntiAlias;

  final FilterQuality filterQuality;

  final bool splitInvert;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final displaySize = splitWideImageDisplaySize(imageSize);
    final fitted = applyBoxFit(fit ?? BoxFit.scaleDown, displaySize, size);
    final destination = alignment.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final slices = splitWideImageSlices(
      invert:
          splitInvert ^
          (matchTextDirection && textDirection == TextDirection.rtl),
    );
    final paint = Paint()
      ..isAntiAlias = isAntiAlias
      ..filterQuality = filterQuality
      ..invertColors = invertColors;
    if (color != null) {
      paint.colorFilter = ColorFilter.mode(
        color!,
        colorBlendMode ?? BlendMode.srcIn,
      );
    }

    for (final slice in slices) {
      final source = Rect.fromLTWH(
        imageSize.width * slice.sourceLeft,
        0,
        imageSize.width * slice.sourceWidth,
        imageSize.height,
      );
      final target = Rect.fromLTWH(
        destination.left,
        destination.top + destination.height * slice.displayTop,
        destination.width,
        destination.height * slice.displayHeight,
      );
      canvas.drawImageRect(image, source, target, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplitWideImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.color != color ||
        oldDelegate.colorBlendMode != colorBlendMode ||
        oldDelegate.fit != fit ||
        oldDelegate.alignment != alignment ||
        oldDelegate.matchTextDirection != matchTextDirection ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.invertColors != invertColors ||
        oldDelegate.isAntiAlias != isAntiAlias ||
        oldDelegate.filterQuality != filterQuality ||
        oldDelegate.splitInvert != splitInvert;
  }
}
