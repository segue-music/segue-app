import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _channel = MethodChannel('segue/device');

/// Whether the app runs on a TV (Android TV, Google TV), asked of Android, which knows by its UI
/// mode (MainActivity.kt). Elsewhere there is no such channel, and it is no TV.
Future<bool> isTelevision() async {
  try {
    return await _channel.invokeMethod<bool>('isTelevision') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// Whether the device can go online through mobile data, which a data plan counts: asked of Android, which knows by its
/// features (a phone, a tablet with a SIM; not a TV), in MainActivity.kt, and of iOS (an iPhone, an iPad with a SIM),
/// in AppDelegate.swift. Elsewhere there is no such channel, and it can't: a computer goes by Wi-Fi or a cable.
Future<bool> hasMobileData() async {
  try {
    return await _channel.invokeMethod<bool>('hasMobileData') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// On a TV, the focus always shows. Flutter starts Android as if it were touched, and shows the
/// focus only after a key from a hardware keyboard; but a TV has no touch screen, and a remote's
/// keys can come as a virtual keyboard's (adb's do), which Flutter doesn't count.
/// Returns whether it is one.
Future<bool> adaptToTelevision() async {
  final television = await isTelevision();

  if (television) {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  }

  return television;
}

/// The device's name, as its owner knows it: on Android, the one in the system settings, or else its
/// maker and model (MainActivity.kt); on iOS, the one in Settings, which since iOS 16 takes an
/// entitlement from Apple, or else "iPhone" or "iPad" (AppDelegate.swift); elsewhere, the computer's.
Future<String> systemDeviceName() async {
  try {
    final name = await _channel.invokeMethod<String>('deviceName');

    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
  } on MissingPluginException {
    // no such channel: not Android
  }

  return Platform.isIOS ? 'iPhone' : Platform.localHostname;
}

/// Keeps the screen on while it is in the tree, as the lyrics full screen do, which are read rather than touched:
/// Android's window keeps it on (MainActivity.kt), and iOS's idle timer is off (AppDelegate.swift). Elsewhere there is
/// no such channel, and the screen goes off as the system has it.
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({required this.child, super.key});

  final Widget child;

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  /// How many are in the tree: one that opens as another is still closing (the lyrics minimized and maximized again at
  /// once) keeps the screen on after that one goes.
  static var _count = 0;

  @override
  void initState() {
    super.initState();

    if (_count++ == 0) {
      _keepScreenOn(true);
    }
  }

  @override
  void dispose() {
    if (--_count == 0) {
      _keepScreenOn(false);
    }

    super.dispose();
  }

  Future<void> _keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', on);
    } on MissingPluginException {
      // no such channel: not a phone or a tablet
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
