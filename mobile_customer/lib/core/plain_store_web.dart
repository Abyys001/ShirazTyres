import 'package:web/web.dart' as web;

/// Whether the encrypted store can run here at all.
///
/// It encrypts through `crypto.subtle`, which a browser exposes only in a
/// secure context. Asked on a cold start rather than waiting to be told by a
/// failure: reading a key that was never written returns null without going
/// near `subtle`, so a session stored on the last page load would otherwise
/// look like no session at all and the app would open on its sign-in screen.
bool plainStoreRequired() => !web.window.isSecureContext;

/// `localStorage`, used only where the encrypted store cannot run.
/// See [AppStorage] for what that costs.
String? plainRead(String key) => web.window.localStorage.getItem(key);

void plainWrite(String key, String value) => web.window.localStorage.setItem(key, value);

void plainDelete(String key) => web.window.localStorage.removeItem(key);
