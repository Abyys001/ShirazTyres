{{flutter_js}}
{{flutter_build_config}}

// Render into the phone-sized element in index.html instead of the whole page.
// On a desktop these builds are a demo of a handset app, and a sign-in form
// stretched across a 27-inch monitor tells you nothing about how it looks in a
// technician's hand. `hostElement` is Flutter's supported way to do this; the
// element fills the window on a small screen, so a real phone is unaffected.
_flutter.loader.load({
  config: {
    hostElement: document.querySelector('#phone-screen'),
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
