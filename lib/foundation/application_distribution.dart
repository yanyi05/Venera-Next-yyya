/// Build-time override lets another fork reuse the same update implementation.
abstract final class ApplicationDistribution {
  static const repository = String.fromEnvironment(
    'VENERA_RELEASE_REPOSITORY',
    defaultValue: 'yanyi05/Venera-Next-yyya',
  );
  static const releasesUrl = 'https://github.com/$repository/releases';
  static const upstreamReleasesUrl =
      'https://github.com/CyrilPeng/Venera-Next/releases';
}
