import '../core/api_client.dart';
import '../core/config.dart';
import '../models/json.dart';

/// The development sign-in list, read from the API instead of compiled in.
///
/// Guarded on both sides. The server serves this only from a DEBUG build over
/// plain http; the app only asks when [AppConfig.devSignInEnabled] agrees. A
/// failure is never surfaced as an error — the panel is a convenience, and a
/// sign-in screen that shows a red box because a helper could not load would be
/// worse than one that simply shows no helper.
class DevAccountsApi {
  const DevAccountsApi(this._client);

  final ApiClient _client;

  Future<DevAccounts> fetch() async {
    if (!AppConfig.devSignInEnabled) return const DevAccounts.empty();
    try {
      final data = asMap(await _client.get('/auth/dev/accounts'));
      return DevAccounts(
        accounts: asList(data['drivers'])
            .map((entry) => DevAccount.fromJson(asMap(entry)))
            .where((account) => account.phone.isNotEmpty)
            .toList(growable: false),
        googleMock: data['google_mock'] == null ? '' : asString(data['google_mock']),
      );
    } catch (_) {
      return const DevAccounts.empty();
    }
  }
}

class DevAccounts {
  const DevAccounts({required this.accounts, required this.googleMock});

  const DevAccounts.empty() : accounts = const <DevAccount>[], googleMock = '';

  final List<DevAccount> accounts;

  /// Section 4.1: with `GOOGLE_OAUTH_MOCK=1` the API accepts this in place of a
  /// real ID token, which is what lets the Google route be exercised without
  /// OAuth credentials. Empty when the mock is off.
  final String googleMock;
}
