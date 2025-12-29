/// Clerk Authentication Configuration
///
/// This file contains configuration for Clerk authentication service
class ClerkConfig {
  // Clerk publishable key (safe to expose in client-side code)
  // Get this from Clerk Dashboard > API Keys
  static const String publishableKey = 'pk_test_c2F2aW5nLWdvYXQtMjUuY2xlcmsuYWNjb3VudHMuZGV2JA';

  // Backend API URL
  // Update this to your production URL when deploying
  static const String backendUrl = 'http://localhost:3000';

  // Clerk Frontend API URL (automatically derived from publishable key)
  // Format: https://{clerk-subdomain}.clerk.accounts.dev
  static String get clerkFrontendApi {
    // Extract subdomain from publishable key
    // pk_test_c2F2aW5nLWdvYXQtMjUuY2xlcmsuYWNjb3VudHMuZGV2JA -> saving-goat-25.clerk.accounts.dev
    return 'https://saving-goat-25.clerk.accounts.dev';
  }

  // API endpoints
  static const String authMeEndpoint = '/auth/me';
  static const String clerkLogoutEndpoint = '/auth/clerk-logout';

  // Session configuration
  static const String sessionTokenKey = 'clerk_session_token';
  static const String userDataKey = 'clerk_user_data';

  // Token expiry (in seconds) - should match backend configuration
  static const int tokenExpirySeconds = 3600; // 1 hour
}
