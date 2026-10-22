import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_details/actions.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/features/history/history_api.dart';

History saved(int ep, {int? group, String? title, String? groupTitle}) =>
    History.fromMap({
      'type': 1,
      'time': 0,
      'title': 'Manga',
      'subtitle': '',
      'cover': '',
      'ep': ep,
      'page': 1,
      'id': 'manga',
      'readEpisode': ['1', '568', '577'],
      'max_page': 10,
      'chapter_group': group,
      'chapter_title': title,
      'group_title': groupTitle,
    });

void main() {
  final chapters = ComicChapters({
    for (var i = 1; i <= 600; i++) 'id-$i': 'Chapter $i',
  });
  test(
    '512 downloads 513 through 522 regardless of unread or highest visited',
    () {
      final plan = NextChapterDownloadPlan.fromHistory(
        chapters: chapters,
        history: saved(512),
      )!;
      expect(plan.indices.map((i) => chapters.ids.elementAt(i)), [
        for (var i = 513; i <= 522; i++) 'id-$i',
      ]);
      expect(plan.currentTitle, 'Chapter 512');
      expect(
        NextChapterDownloadPlan.fromHistory(
          chapters: chapters,
          history: saved(300),
        )!.indices.first,
        300,
      );
    },
  );
  test(
    'downloaded entries are skipped within the ten, without extending window',
    () {
      final plan = NextChapterDownloadPlan.fromHistory(
        chapters: chapters,
        history: saved(512),
        downloadedIds: {'id-513', 'id-520'},
      )!;
      expect(plan.indices, [513, 514, 515, 516, 517, 518, 520, 521]);
    },
  );
  test('end, missing history and invalid positions', () {
    expect(
      NextChapterDownloadPlan.fromHistory(
        chapters: chapters,
        history: saved(598),
      )!.indices,
      [598, 599],
    );
    expect(
      NextChapterDownloadPlan.fromHistory(
        chapters: chapters,
        history: saved(600),
      )!.indices,
      isEmpty,
    );
    for (final history in [null, saved(0), saved(601), saved(2, group: 1)]) {
      expect(
        NextChapterDownloadPlan.fromHistory(
          chapters: chapters,
          history: history,
        ),
        isNull,
      );
    }
  });
  test(
    'uses source list order and IDs, not chapter numbers parsed from names',
    () {
      const irregular = ComicChapters({
        'z': '512',
        'a': 'Special',
        'b': '518',
        'c': '519 part 2',
      });
      expect(
        NextChapterDownloadPlan.fromHistory(
          chapters: irregular,
          history: saved(1),
        )!.indices,
        [1, 2, 3],
      );
    },
  );
  test('group coordinates cross into following groups in source order', () {
    const grouped = ComicChapters.grouped({
      'Volume 1': {'a': 'First', 'b': 'Second'},
      'Volume 2': {'c': 'Third', 'd': 'Fourth'},
      'Volume 3': {'e': 'Fifth'},
    });
    expect(
      NextChapterDownloadPlan.fromHistory(
        chapters: grouped,
        history: saved(1, group: 2),
      )!.indices,
      [3, 4],
    );
    expect(
      NextChapterDownloadPlan.fromHistory(
        chapters: grouped,
        history: saved(3, group: 1),
      ),
      isNull,
    );
    expect(
      NextChapterDownloadPlan.fromHistory(
        chapters: grouped,
        history: saved(1, group: 4),
      ),
      isNull,
    );
  });
  test(
    'source insertions recover exact saved names; ambiguous or removed names fail closed',
    () {
      const changed = ComicChapters({
        'x': 'New',
        'a': 'Original',
        'b': 'Next',
        'c': 'Duplicate',
        'd': 'Duplicate',
      });
      expect(
        NextChapterDownloadPlan.fromHistory(
          chapters: changed,
          history: saved(1, title: 'Original'),
        )!.indices,
        [2, 3, 4],
      );
      for (final title in ['Removed', 'Duplicate']) {
        expect(
          NextChapterDownloadPlan.fromHistory(
            chapters: changed,
            history: saved(1, title: title),
          ),
          isNull,
        );
      }
    },
  );
}
