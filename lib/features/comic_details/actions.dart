import 'package:venera_next/features/favorites/favorites_scope.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/side_bar.dart';
import 'package:venera_next/components/window_frame.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/features/comic_details/archive_download_dialog.dart';
import 'package:venera_next/features/comic_details/comments_page.dart';
import 'package:venera_next/features/comic_details/favorite.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/favorites/favorites_api.dart';
import 'package:venera_next/features/favorites/read_later.dart';
import 'package:venera_next/features/history/history_api.dart';
import 'package:venera_next/features/history/history_scope.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/local_comics/download.dart';
import 'package:venera_next/features/reader/reader.dart';
import 'package:venera_next/features/search/search_shortcut.dart';
import 'package:venera_next/features/search/search_shortcuts.dart';
import 'package:venera_next/routing/app_navigation.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/file_interaction.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/navigation_admission.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/routing/page_jump_target.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/features/comic_details/rating_dialog.dart';

abstract mixin class ComicPageActions {
  void update();

  BuildContext get context;

  MenuRouteController get contextMenus;

  bool isComicActive(ComicDetails value);

  ComicDetails get comic;

  ComicSource get comicSource => ComicSource.find(comic.sourceKey)!;

  History? get history;

  ComicDetails? _likingComic;

  bool get isLiking => _likingComic != null && isComicActive(_likingComic!);

  bool isLiked = false;

  Future<void> likeOrUnlike() async {
    if (isLiking) return;
    final target = comic;
    final wasLiked = isLiked;
    _likingComic = target;
    update();
    Res<bool> result;
    try {
      result = await comicSource.likeOrUnlikeComic!(target.id, wasLiked);
    } catch (error, stack) {
      result = Res.fromException(error, stack);
    } finally {
      if (identical(_likingComic, target)) _likingComic = null;
    }
    if (!isComicActive(target)) return;
    if (result.error) {
      final currentContext = context;
      if (currentContext.mounted) {
        currentContext.showMessage(message: result.errorMessage!);
      }
    } else {
      isLiked = !wasLiked;
    }
    update();
  }

  /// whether the comic is added to local favorite
  bool isAddToLocalFav = false;

  /// whether the comic is favorite on the server
  bool isFavorite = false;

  FavoriteItem _toFavoriteItem() {
    var tags = <String>[];
    for (var e in comic.tags.entries) {
      tags.addAll(e.value.map((tag) => '${e.key}:$tag'));
    }
    return FavoriteItem(
      id: comic.id,
      name: comic.title,
      coverPath: comic.cover,
      author: comic.subTitle ?? comic.uploader ?? '',
      type: comic.comicType,
      tags: tags,
    );
  }

  void openFavPanel() {
    final target = comic;
    final owner = context;
    showSideBar(
      appNavigation.rootContext,
      ComicFavoritePanel(
        cid: comic.id,
        type: comic.comicType,
        isFavorite: isFavorite,
        onFavorite: (local, network) {
          if (!owner.mounted || !isComicActive(target)) return;
          if (network != null) {
            isFavorite = network;
          }
          if (local != null) {
            isAddToLocalFav = local;
          }
          update();
        },
        favoriteItem: _toFavoriteItem(),
        updateTime: comic.findUpdateTime(),
      ),
    );
  }

  ComicDetails? _addingQuickFavorite;

  Future<void> quickFavorite() async {
    if (_addingQuickFavorite != null) return;
    var folder = GlobalPreferenceStore(
      appdata.settings,
    ).read(FavoritePreferences.quickFavorite);
    if (folder == null) {
      return;
    }
    final owner = context;
    final target = comic;
    final item = _toFavoriteItem();
    final updateTime = target.findUpdateTime();
    final manager = FavoritesScope.read(context);
    final generation = manager.connectionGeneration;
    _addingQuickFavorite = target;
    try {
      await AppDataOperations.instance.access(() async {
        if (!owner.mounted || !isComicActive(target)) return;
        if (manager.connectionGeneration != generation) {
          throw StateError('Favorites database changed. Try again.');
        }
        await manager.addComic(folder, item, null, updateTime);
      });
      if (!owner.mounted || !isComicActive(target)) return;
      isAddToLocalFav = true;
      update();
      owner.showMessage(
        message: 'Added to @folder'.tlParams({'folder': folder}),
      );
    } catch (error, stack) {
      Log.error('Quick favorite', error, stack);
      if (owner.mounted && isComicActive(target)) {
        owner.showMessage(message: error.toString());
      }
    } finally {
      if (identical(_addingQuickFavorite, target)) _addingQuickFavorite = null;
    }
  }

  Widget buildReadLaterAction() => ReadLaterButton(
    comic: _toFavoriteItem(),
    onChanged: () {
      isAddToLocalFav = FavoritesScope.read(
        context,
      ).isExist(comic.id, comic.comicType);
      update();
    },
  );

  Future<void>? _sharing;

  Future<void> share() {
    if (_sharing case final pending?) return pending;
    final owner = context;
    if (!NavigationAdmission.allows(owner)) return Future.value();
    final target = comic;
    final route = ModalRoute.of(owner);
    bool isCurrentOwner() =>
        owner.mounted &&
        isComicActive(target) &&
        route?.isCurrent != false &&
        identical(ModalRoute.of(owner), route);
    final text =
        '${target.title}${target.url == null ? '' : '\n${target.url}'}';
    final window = owner.getInheritedWidgetOfExactType<WindowFrameController>();
    final operation = () async {
      try {
        await Share.shareText(
          text,
          resolveOrigin: () => owner.sharePositionOrigin,
          canShare: () =>
              isCurrentOwner() &&
              window?.isClosing != true &&
              NavigationAdmission.allows(owner),
        );
      } catch (error, stack) {
        Log.error('Share', error, stack);
        if (owner.mounted && isCurrentOwner() && window?.isClosing != true) {
          owner.showMessage(message: 'Error'.tl);
        } else {
          Error.throwWithStackTrace(error, stack);
        }
      }
    }();
    _sharing = operation;
    // Queued requests check admission again before opening native UI. Once
    // dispatched, the window must join acknowledgment even after page removal.
    window?.trackExitTask(operation);
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_sharing, operation)) _sharing = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_sharing, operation)) _sharing = null;
        },
      ),
    );
    return operation;
  }

  /// read the comic
  ///
  /// [ep] the episode number, start from 1
  ///
  /// [page] the page number, start from 1
  ///
  /// [group] the chapter group number, start from 1
  void read([int? ep, int? page, int? group]) {
    appNavigation.rootContext
        .to(
          () => Reader(
            onClosed: ReaderSessionScope.onClosedOf(appNavigation.rootContext),
            type: comic.comicType,
            cid: comic.id,
            name: comic.title,
            chapters: comic.chapters,
            initialChapter: ep,
            initialPage: page,
            initialChapterGroup: group,
            history: history ?? History.fromModel(model: comic, ep: 0, page: 0),
            author: comic.findAuthor() ?? '',
            tags: comic.plainTags,
          ),
        )
        .then((_) {
          onReadEnd();
        });
  }

  void continueRead() {
    var ep = history?.ep ?? 1;
    var page = history?.page ?? 1;
    var group = history?.group;
    read(ep, page, group);
  }

  void onReadEnd();

  bool _choosingDownload = false;

  Future<void> download() async {
    if (_choosingDownload) return;
    final owner = context;
    if (!owner.mounted) return;
    final admission = WindowSelectionTask(owner);
    if (!admission.canPresent) return;
    final target = comic;
    final source = comicSource;
    final library = LocalManager();
    bool canContinue() => admission.canPresent && isComicActive(target);
    if (!canContinue()) return;
    _choosingDownload = true;
    try {
      if (library.isDownloading(target.id, target.comicType)) {
        owner.showMessage(message: "The comic is downloading".tl);
        return;
      }
      if (target.chapters == null &&
          library.isDownloaded(target.id, target.comicType, 0)) {
        owner.showMessage(message: "The comic is downloaded".tl);
        return;
      }

      if (source.archiveDownloader != null) {
        final selection = await showArchiveDownloadDialog(
          context: owner,
          downloader: source.archiveDownloader!,
          comicId: target.id,
        );
        if (!owner.mounted || !canContinue() || selection == null) {
          return;
        }
        if (selection.url != null) {
          if (library.isDownloading(target.id, target.comicType)) return;
          library.addTask(
            ArchiveDownloadTask(selection.url!, target, storage: library),
          );
          owner.showMessage(message: "Download started".tl);
          update();
          return;
        }
      }

      if (!owner.mounted || !canContinue()) return;
      if (library.isDownloading(target.id, target.comicType)) return;
      if (target.chapters == null) {
        library.addTask(
          ImagesDownloadTask(
            storage: library,
            source: source,
            comicId: target.id,
            comic: target,
          ),
        );
      } else {
        final chapterIds = List<String>.unmodifiable(target.chapters!.ids);
        final chapterTitles = List<String>.unmodifiable(
          target.chapters!.titles,
        );
        var downloaded = <int>[];
        var localComic = library.find(target.id, target.comicType);
        if (localComic != null) {
          for (int i = 0; i < chapterIds.length; i++) {
            if (localComic.downloadedChapters.contains(chapterIds[i])) {
              downloaded.add(i);
            }
          }
        }
        final historyStore = HistoryScope.read(owner);
        final historyGeneration = historyStore.connectionGeneration;
        NextChapterDownloadPlan? nextTen() {
          if (!owner.mounted ||
              !admission.active ||
              !isComicActive(target) ||
              !historyStore.isInitialized ||
              historyStore.connectionGeneration != historyGeneration ||
              !identical(HistoryScope.read(owner), historyStore)) {
            return null;
          }
          return NextChapterDownloadPlan.fromHistory(
            chapters: target.chapters!,
            history: historyStore.find(target.id, target.comicType),
            downloadedIds:
                library
                    .find(target.id, target.comicType)
                    ?.downloadedChapters
                    .toSet() ??
                <String>{},
          );
        }

        final selected = await showSideBar<List<int>>(
          owner,
          _SelectDownloadChapter(
            chapterTitles,
            List<int>.unmodifiable(downloaded),
            nextTen: nextTen,
            isCurrent: () =>
                owner.mounted && admission.active && isComicActive(target),
          ),
        );
        if (!owner.mounted ||
            !canContinue() ||
            selected == null ||
            selected.isEmpty) {
          return;
        }
        if (library.isDownloading(target.id, target.comicType)) return;
        library.addTask(
          ImagesDownloadTask(
            storage: library,
            source: source,
            comicId: target.id,
            comic: target,
            chapters: selected.map((i) => chapterIds[i]).toList(),
          ),
        );
      }
      owner.showMessage(message: "Download started".tl);
      update();
    } catch (error, stack) {
      Log.error('Download selection', error, stack);
      if (owner.mounted && canContinue()) {
        owner.showMessage(message: error.toString());
      }
    } finally {
      _choosingDownload = false;
    }
  }

  void onTapTag(String tag, String namespace) {
    var target = searchTargetForTag(tag, namespace);
    var context = appNavigation.mainNavigatorKey!.currentContext!;
    target?.jump(context);
  }

  PageJumpTarget? searchTargetForTag(String tag, String namespace) {
    return comicSource.handleClickTagEvent?.call(namespace, tag);
  }

  void onLongPressTag(String tag, String namespace, BuildContext tagContext) {
    final target = comic;
    final renderBox = tagContext.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final shortcut = searchTargetForTag(tag, namespace) == null
        ? null
        : SearchShortcut(
            kind: isAuthorNamespace(namespace)
                ? SearchShortcutKind.author
                : SearchShortcutKind.tag,
            sourceKey: comic.sourceKey,
            namespace: namespace,
            value: tag,
          );
    showSearchShortcutMenu(
      menus: contextMenus,
      isValid: () => isComicActive(target),
      context: tagContext,
      location: Offset(
        offset.dx + renderBox.size.width / 2 - 121,
        offset.dy + renderBox.size.height - 8,
      ),
      copyText: tag,
      shortcut: shortcut,
    );
  }

  void showMoreActions() {
    final target = comic;
    contextMenus.show(
      context,
      Offset(context.width - 16, context.padding.top),
      [
        MenuEntry(
          icon: Icons.copy,
          text: "Copy Title".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: target.title));
            context.showMessage(message: "Copied".tl);
          },
        ),
        MenuEntry(
          icon: Icons.copy_rounded,
          text: "Copy ID".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: target.id));
            context.showMessage(message: "Copied".tl);
          },
        ),
        if (target.url != null)
          MenuEntry(
            icon: Icons.link,
            text: "Copy URL".tl,
            onClick: () {
              Clipboard.setData(ClipboardData(text: target.url!));
              context.showMessage(message: "Copied".tl);
            },
          ),
        if (target.url != null)
          MenuEntry(
            icon: Icons.open_in_browser,
            text: "Open in Browser".tl,
            onClick: () {
              launchUrlString(target.url!);
            },
          ),
      ],
      isValid: () => isComicActive(target),
    );
  }

  void showComments() {
    showSideBar(
      appNavigation.rootContext,
      CommentsPage(data: comic, source: comicSource),
    );
  }

  void starRating() {
    final source = comicSource;
    if (!source.isLogged) return;
    final id = comic.id;
    showDialog<void>(
      context: context,
      builder: (_) => ComicRatingDialog(
        submit: (rating) => source.starRatingFunc!(id, rating),
      ),
    );
  }
}

class _SelectDownloadChapter extends StatefulWidget {
  const _SelectDownloadChapter(
    this.eps,
    this.downloadedEps, {
    required this.isCurrent,
    required this.nextTen,
  });

  final NextChapterDownloadPlan? Function() nextTen;
  final List<String> eps;
  final List<int> downloadedEps;
  final bool Function() isCurrent;

  @override
  State<_SelectDownloadChapter> createState() => _SelectDownloadChapterState();
}

class _SelectDownloadChapterState extends State<_SelectDownloadChapter> {
  List<int> selected = [];
  WindowSelectionTask? _owner;
  NavigatorState? _navigator;
  Object _generation = Object();
  bool _confirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A surviving sidebar never adopts a replacement application or window.
    _owner ??= WindowSelectionTask(context);
    _navigator ??= Navigator.of(context);
  }

  @override
  void didUpdateWidget(covariant _SelectDownloadChapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eps != widget.eps ||
        oldWidget.downloadedEps != widget.downloadedEps ||
        oldWidget.isCurrent != widget.isCurrent) {
      _generation = Object();
      selected = [];
    }
  }

  bool _canSelect(Object generation) =>
      mounted &&
      identical(generation, _generation) &&
      !_confirming &&
      _owner?.canPresent == true &&
      Navigator.maybeOf(context) == _navigator &&
      widget.isCurrent();

  void _submit(Object generation, List<int> selection) {
    if (!_canSelect(generation)) return;
    _confirming = true;
    try {
      _navigator!.pop<List<int>>(List<int>.unmodifiable(selection));
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final active = _canSelect(generation);
    final eps = widget.eps;
    final downloaded = widget.downloadedEps;
    final plan = widget.nextTen();
    return Scaffold(
      appBar: Appbar(
        title: Text("Download".tl),
        backgroundColor: context.colorScheme.surfaceContainerLow,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text('Download next 10 chapters'.tl),
                  onPressed: !active || plan == null || plan.indices.isEmpty
                      ? null
                      : () {
                          if (!_canSelect(generation)) return;
                          // Re-read saved progress and downloads at the click,
                          // including changes made while this sheet was open.
                          final latest = widget.nextTen();
                          if (latest == null || latest.indices.isEmpty) {
                            setState(() {});
                            return;
                          }
                          _submit(generation, latest.indices);
                        },
                ),
                const SizedBox(height: 4),
                Text(
                  plan == null
                      ? 'Read a chapter first, or select chapters manually.'.tl
                      : plan.indices.isEmpty
                      ? 'No remaining chapters to download in the next 10.'.tl
                      : 'After @chapter: download @count chapters'.tlParams({
                          'chapter': plan.currentTitle,
                          'count': plan.indices.length.toString(),
                        }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: eps.length,
              itemBuilder: (context, i) {
                return CheckboxListTile(
                  title: Text(eps[i]),
                  value: selected.contains(i) || downloaded.contains(i),
                  onChanged: !active || downloaded.contains(i)
                      ? null
                      : (v) {
                          if (!_canSelect(generation)) return;
                          setState(() {
                            if (selected.contains(i)) {
                              selected.remove(i);
                            } else {
                              selected.add(i);
                            }
                          });
                        },
                );
              },
            ),
          ),
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextButton(
                    onPressed: !active
                        ? null
                        : () {
                            final res = <int>[];
                            for (int i = 0; i < eps.length; i++) {
                              if (!downloaded.contains(i)) res.add(i);
                            }
                            _submit(generation, res);
                          },
                    child: Text("Download All".tl),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: !active || selected.isEmpty
                        ? null
                        : () {
                            if (selected.isEmpty) return;
                            _submit(generation, selected);
                          },
                    child: Text("Download Selected".tl),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// A manual download window after the last saved position, never the highest
/// visited chapter or the earliest unread chapter. Indices are zero-based.
class NextChapterDownloadPlan {
  const NextChapterDownloadPlan(this.currentTitle, this.indices);

  final String currentTitle;
  final List<int> indices;

  static NextChapterDownloadPlan? fromHistory({
    required ComicChapters chapters,
    required History? history,
    Set<String> downloadedIds = const {},
  }) {
    if (history == null || history.ep < 1 || chapters.length == 0) return null;
    var group = history.group;
    var offset = 0;
    var titles = chapters.titles.toList();
    if (group != null) {
      if (!chapters.isGrouped) return null;
      final groupTitle = history.groupTitle;
      if (groupTitle != null && groupTitle.isNotEmpty) {
        final found = chapters.groups.toList().indexOf(groupTitle);
        if (found < 0) return null;
        group = found + 1;
      }
      if (group < 1 || group > chapters.groupCount) return null;
      for (var i = 0; i < group - 1; i++) {
        offset += chapters.getGroupByIndex(i).length;
      }
      titles = chapters.getGroupByIndex(group - 1).values.toList();
    }
    var current = history.ep - 1;
    final savedTitle = history.chapterTitle;
    if (savedTitle != null &&
        savedTitle.isNotEmpty &&
        (current >= titles.length || titles[current] != savedTitle)) {
      // Recover from source list insertions only for an unambiguous exact name.
      final matches = <int>[
        for (var i = 0; i < titles.length; i++)
          if (titles[i] == savedTitle) i,
      ];
      if (matches.length != 1) return null;
      current = matches.single;
    }
    if (current >= titles.length) return null;
    final flat = offset + current;
    final ids = chapters.ids.toList();
    final selected = <int>[];
    final seen = <String>{};
    for (var i = flat + 1; i < ids.length && i <= flat + 10; i++) {
      if (!downloadedIds.contains(ids[i]) && seen.add(ids[i])) selected.add(i);
    }
    return NextChapterDownloadPlan(
      titles[current],
      List.unmodifiable(selected),
    );
  }
}
