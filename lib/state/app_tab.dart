import 'package:flutter/foundation.dart';

/// Which tab the shell's IndexedStack shows. Provided app-wide so any
/// screen (e.g. Home quick tiles) can drive bottom navigation.
class AppTab extends ChangeNotifier {
  int _index = 0;
  int get index => _index;

  void switchTo(int index) {
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }
}
