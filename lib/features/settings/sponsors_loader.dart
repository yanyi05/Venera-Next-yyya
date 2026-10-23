import 'dart:convert';

import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/network/app_dio.dart';

import 'sponsor_catalog.dart';

const _sources = [
  "https://cdn.jsdelivr.net/gh/yanyi05/Venera-Next-yyya@reader-mask-tools/sponsors.json",
  "https://raw.githubusercontent.com/yanyi05/Venera-Next-yyya/reader-mask-tools/sponsors.json",
];

typedef SponsorsLoader = Future<SponsorCatalog> Function();

Future<SponsorCatalog> fetchSponsors() async {
  Object? lastError;
  for (var url in _sources) {
    try {
      var res = await AppDio().get(
        url,
        options: Options(headers: {"cache-time": "long"}),
      );
      if (res.statusCode == 200) {
        var data = res.data is String ? jsonDecode(res.data) : res.data;
        return SponsorCatalog.fromJson(data);
      }
    } catch (error, stackTrace) {
      lastError = error;
      Log.error(
        "Sponsors",
        "Failed to fetch sponsors from $url: $error",
        stackTrace,
      );
    }
  }
  if (lastError != null) {
    throw lastError;
  }
  throw const FormatException("No sponsor source returned a valid response");
}
