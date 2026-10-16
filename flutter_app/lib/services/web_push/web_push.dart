// Notifications web : le relais JavaScript de `web/index.html` sur le web,
// une version neutre ailleurs (`dart:js_interop` n'existe que sur le web).
export 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart';
