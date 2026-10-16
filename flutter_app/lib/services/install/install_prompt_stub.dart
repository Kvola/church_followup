// Hors navigateur : rien à installer, rien à proposer.
bool isStandalone() => false;
bool canPromptInstall() => false;
Future<bool> promptInstall() async => false;
