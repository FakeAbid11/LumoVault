package com.lumovault.app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Hosts the Flutter engine.
 *
 * Extends FlutterFragmentActivity rather than FlutterActivity because
 * local_auth's Android implementation shows BiometricPrompt from a
 * FragmentActivity; with a plain FlutterActivity it fails at runtime.
 */
class MainActivity : FlutterFragmentActivity()
