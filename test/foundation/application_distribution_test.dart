import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/application_distribution.dart';
import 'package:venera_next/foundation/application_update_service.dart';
import 'package:venera_next/network/app_dio.dart';
import '../support/application_update_adapter.dart';

void main() {
  test('default update channel targets yyya fork', () async {
    final adapter = ApplicationUpdateAdapter()..released.complete();
    final service = ApplicationUpdateService(
      createClient: () => Dio()..httpClientAdapter = adapter,
      currentVersion: () => '1.18.0',
    );
    final checked = service.check();
    await adapter.entered.future;
    adapter.complete({'tag_name': 'v1.18.3'});
    expect(await checked, '1.18.3');
    expect(
      adapter.paths.single,
      'https://api.github.com/repos/yanyi05/Venera-Next-yyya/releases/latest',
    );
    expect(
      ApplicationDistribution.releasesUrl,
      contains('yanyi05/Venera-Next-yyya'),
    );
    await service.closeAndWait();
  });
  test(
    'fork with no releases is not an update failure and still closes client',
    () async {
      final adapter = ApplicationUpdateAdapter()..released.complete();
      final service = ApplicationUpdateService(
        createClient: () => Dio()..httpClientAdapter = adapter,
        currentVersion: () => '1.18.3',
      );
      final checked = service.check();
      await adapter.entered.future;
      adapter.complete({'message': 'Not Found'}, status: 404);
      expect(await checked, isNull);
      expect(adapter.closes, 1);
      await service.closeAndWait();
    },
  );
}
