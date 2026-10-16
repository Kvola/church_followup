import 'package:church_followup_mobile/screens/attendance/attendance_sunday_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le pointage s\'ouvre sur le dernier dimanche', () {
    // Vendredi 16 octobre 2026 → dimanche 11.
    expect(lastSunday(DateTime(2026, 10, 16, 18)), DateTime(2026, 10, 11));
    // Un dimanche reste ce dimanche.
    expect(lastSunday(DateTime(2026, 10, 11, 9)), DateTime(2026, 10, 11));
    // Lundi → la veille.
    expect(lastSunday(DateTime(2026, 10, 12)), DateTime(2026, 10, 11));
  });
}
