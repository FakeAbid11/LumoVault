import 'package:flutter/material.dart';

/// Standard scaffold used throughout LumoVault.
///
/// Adds shared behavior beyond raw [Scaffold]:
/// - [useSafeArea] wraps the body in a [SafeArea] (default `true`).
class LumoScaffold extends StatelessWidget {
  const LumoScaffold({
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.useSafeArea = true,
    super.key,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: useSafeArea ? SafeArea(child: body) : body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      endDrawer: endDrawer,
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}
