class TenorConfig {
  // Get your free API key from: https://developers.google.com/tenor/guides/quickstart
  static const String apiKey = 'AIzaSyAyimkuYQYF_FXVALexPuGQctUWRURdCYQ'; // Demo key
  static const String baseUrl = 'https://tenor.googleapis.com/v2';

  // API endpoints
  static const String searchEndpoint = '/search';
  static const String trendingEndpoint = '/featured';
  static const String categoriesEndpoint = '/categories';

  // Default search parameters
  static const int defaultLimit = 20;
  static const String defaultLocale = 'en_US';
  static const String defaultMediaFilter = 'gif,tinygif';
}
