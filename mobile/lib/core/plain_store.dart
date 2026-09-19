/// Off the web there is no fallback and none is wanted: a device keystore that
/// refuses is a device to fix, not one to start writing tokens in the clear on.
bool plainStoreRequired() => false;

String? plainRead(String key) => null;

void plainWrite(String key, String value) {}

void plainDelete(String key) {}
