// Ce que le navigateur sait de l'installation de la PWA.
//
// Sur le web, le relais JavaScript de `web/index.html` ; ailleurs (APK,
// tests), une version neutre : `dart:js_interop` n'existe que sur le web.
export 'install_prompt_stub.dart' if (dart.library.js_interop) 'install_prompt_web.dart';
