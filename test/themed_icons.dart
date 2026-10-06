import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/themed_icon.dart';

/// The app's icons that draw [icon], as `find.byIcon` finds a font's.
Finder themedIcon(HugeIconData icon) => find.byWidgetPredicate((widget) => widget is ThemedIcon && widget.icon == icon);
