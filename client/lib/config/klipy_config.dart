class KlipyConfig {
  // Get your API key from https://klipy.com/developers
  static const String apiKey = '6ODanRP50dvNEen0nEcJen9V5raWEfX3Pmt29lEmv16CjcEKKoxlvLgNVpT7ow85';

  static const String baseUrl = 'https://api.klipy.com/api/v1';
  static const String searchEndpoint = '/stickers/search';
  static const String trendingEndpoint = '/stickers/trending';
  static const String clipsSearchEndpoint = '/clips/search';
  static const String clipsTrendingEndpoint = '/clips/trending';

  // Default parameters
  static const int defaultLimit = 20;
  static const String defaultLocale = 'en_US';
}
