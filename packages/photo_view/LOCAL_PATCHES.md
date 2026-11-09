# Local photo_view 0.14.0 patch

Source: https://github.com/CyrilPeng/photo_view at commit
`a1255d1b5945aad4b7323303ec2ecdf0c90ffc4c`, previously pinned by the
application. The upstream package identifies
https://github.com/renancaraujo/photo_view as its homepage. Its MIT license is
retained unchanged. VeneraNext maintainers own this local patch.

The sixteen `lib/` files, `pubspec.yaml`, `LICENSE`, and package analysis options
are retained. Git metadata, examples, upstream tests, scripts, and build output
are omitted. The package version remains 0.14.0 and all other application
dependencies retain their complete original lockfile records.

## ImageWrapper dimension-listener ownership

`lib/src/photo_view_wrappers.dart` received an owned ImageInfo clone for each
frame, used its dimensions, then assigned `_imageInfo = _imageInfo`. The clone
was never disposed, including on replacement and unmount. The dimension-only
callback now disposes every received ImageInfo in `finally`, and the unused
field is removed. The independent PhotoViewImage rendering listener retains
and disposes its own clone as before. No fit, sizing, scale, animation, or
gesture behavior is changed.

Original source Git blob SHA-256 (canonical LF bytes):
`88cf568c29d72c3ac0d83503a9b81b85159ecc6c6bca2be0d133e55e52049242`.

The other frame consumer, `lib/src/core/image.dart`, already retains its current
ImageInfo and releases replaced/unmounted frames after a frame. It has no
equivalent discarded-clone defect and receives no ownership change.

## Equivalent current-SDK calls

Three deprecated API calls are replaced without disabling diagnostics:

- `TickerMode.of(context)` becomes `TickerMode.valuesOf(context).enabled` in
  `lib/src/core/image.dart`. Original Git blob SHA-256 (canonical LF bytes):
  `ec752014bd65ef2fe64c2ce6662e141e6ff9c99e1cd1753e46d20dc94ff7b761`.
- In `lib/src/core/photo_view_core.dart`, `translate(dx, dy)` becomes
  `translateByDouble(dx, dy, 0.0, 1.0)` and `scale(s)` becomes
  `scaleByDouble(s, s, s, 1.0)`. These are the exact scalar branches used by
  the locked vector_math 2.2.0 implementation, including scaling all three
  spatial axes and preserving the homogeneous coordinate. Original Git blob
  SHA-256 (canonical LF bytes):
  `a62f543b691e919b3ecd14688084da769d630b7f9c737b66fee8aedee4efdcae`.

All retained Dart sources are normalized by the repository's Dart formatter.
At initial vendoring, apart from the three files above, normalized copies
matched the source commit. The lifecycle patch below adds further changes.
The package manifest, license and original analysis rules remain unchanged.
The analysis options' extra blank line at EOF is removed for diff validation.

## Controller and gesture lifetime

The 2026-10-07 patch changes four retained files:

- `lib/photo_view.dart` cancels and replaces the scale-state subscription,
  distinguishes owned and borrowed controllers, and releases retired owned
  controllers after their actual child subtree unmounts. Replacing one
  controller preserves the other; adopting an internal controller transfers
  ownership to the caller. An offstage layout is not treated as proof that its
  previous child has unmounted.
- `lib/photo_view_gallery.dart` releases its fallback PageController and
  responds to supplied controller changes without disposing borrowed objects.
- `lib/src/controller/photo_view_controller_delegate.dart` detaches both
  original listeners on replacement or disposal and observes new controllers.
- `lib/src/core/photo_view_core.dart` binds external callbacks to the original
  controller and generation, clears only callbacks still owned by that view,
  and rejects delayed gesture completion after replacement, unmount or a new
  gesture. Controller replacement stops the original animations.

The existing public PhotoViewGestureDetectorScope export is unchanged. There
is no dependency, SDK constraint or package version change. The application
gallery owns each page controller in the State of that page's PhotoView
subtree; retained neighbours stay valid until unmount. The original re-entry
subtree replacement is superseded by the in-place reset described below.

`test/controller_lifecycle_test.dart` adds ten package-local widget regressions
for subscriptions, borrowed/owned replacement, offstage disposal, callback
identity, overlapping gestures and gallery fallback ownership. The root
`test/foundation/photo_view_controller_lifecycle_test.dart` imports this suite
so the application's full test run includes it. Expanded application tests
also cover the seven reading modes, mid-scroll removal, image rendering and
image-favorite previews. Generated image fixtures verify layout and bounded
live controllers; they do not replace physical-device acceptance.

## Current-layout zoom baseline

The 2026-10-22 patch makes `getInitialScale()` derive the unzoomed baseline
from the current scale boundaries instead of caching the controller value at
mount. Rotation changes the contained scale even when the controller and page
stay mounted; the stale baseline incorrectly blocked gallery automatic reading
and reset/long-press recovery. The callback keeps its existing controller and
generation ownership guards and does not adopt an active user zoom as its
baseline. Manifest, SDK constraints, package version and license are unchanged.

Application regressions cover both rotations, single and paired pages, all three
gallery directions, interrupted page animation and an actual scale gesture.
Existing frame and controller ownership tests still run unchanged.

## In-place reset and gallery page continuity

The 2026-10-24 patch for #118 keeps an already loaded gallery page mounted when
it becomes active, rather than replacing its image subtree to reset zoom.
`PhotoViewController.reset()` now calls a view-owned reset hook before updating
its value and records the previous value. The hook stops scale, position and
rotation animations, invalidates delayed gesture completion, and ignores the
rest of a gesture that started before the reset. A new gesture works normally.
The scale delegate recognizes the exact initial scale as `initial`, not
`zoomedOut`, so the next double tap still follows the normal zoom cycle.

The reset hook uses the same controller/generation and callback-identity guards
as the other mounted callbacks. Replaced or unmounted views cannot reset a new
view or clear its hook. No controller-base interface, dependency, version, cache
limit or page keep-alive policy changes.

Package lifecycle regressions cover animation cancellation, gesture retirement,
double-tap recovery and stale reset hooks. Application regressions use real
local PNGs to check image element/frame identity and rendered selection-frame
pixels in all three directions, forward and backward, with and without the
global image cache. Interrupted turns also verify retained-page zoom reset;
existing tests continue to bound live controllers and verify unmount cleanup.
These widget tests do not replace iPad or Android physical-device acceptance.

## Validation and dependency resolution

`test/foundation/photo_view_image_ownership_test.dart` uses the real PhotoView,
captured ImageInfo clones and native image handles. It covers initially cached
and asynchronously delivered images, successive frames, frame replacement,
complete unmount cleanup, contained sizing, and animated zoom. The ownership
assertions fail against the unpatched source and pass with this patch.

Use `flutter test --no-pub test/foundation/photo_view_image_ownership_test.dart`.
For dependency resolution, keep PUB_HOSTED_URL consistent with the lockfile's
`https://pub.dev` and use `flutter pub get --offline --enforce-lockfile` with the
existing package cache. An unrelated hosted mirror can otherwise cause Pub to
replace hosted source identities. Reverting this patch requires restoring the
photo_view declarations in both root pubspec files and its Git inventory entry.
