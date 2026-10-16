import 'dart:js_interop';

@JS('suiviIsStandalone')
external JSBoolean? _isStandalone();

@JS('suiviCanInstall')
external JSBoolean? _canInstall();

@JS('suiviPromptInstall')
external JSPromise<JSBoolean>? _promptInstall();

/// L'app est-elle déjà ouverte comme application installée ?
bool isStandalone() {
  try {
    return _isStandalone()?.toDart ?? false;
  } catch (_) {
    return false; // relais absent (index.html ancien) : on se tait
  }
}

/// Le navigateur propose-t-il l'installation (Chrome, Edge, Android) ?
bool canPromptInstall() {
  try {
    return _canInstall()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Ouvre la fenêtre d'installation du navigateur ; rend vrai si acceptée.
Future<bool> promptInstall() async {
  try {
    final promise = _promptInstall();
    if (promise == null) return false;
    return (await promise.toDart).toDart;
  } catch (_) {
    return false;
  }
}
