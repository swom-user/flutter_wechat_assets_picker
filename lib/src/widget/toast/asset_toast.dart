import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class AssetToast {
  static Future<void> show(
    BuildContext context, {
    required String message,
    ToastLength? toastLength,
  }) async {
    showToast(context, message, toastLength: toastLength);
  }
}

enum ToastLength {
  /// Show Short toast for 2 sec
  short,

  /// Show Long toast for 5 sec
  long
}

extension on ToastLength {
  Duration get duration => Duration(seconds: this == ToastLength.short ? 2 : 5);
}

final fToast = FToast();

void showToast(
  BuildContext context,
  String message, {
  ToastLength? toastLength,
}) {
  fToast.init(context);
  final Widget toast = SafeArea(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0),
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(72),
          color: const Color.fromRGBO(0, 0, 0, 0.6),
        ),
        child: Wrap(
          children: [
            Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 16.0,
              ).copyWith(
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    ),
  );

  fToast.showToast(
    child: toast,
    toastDuration: (toastLength ?? ToastLength.short).duration,
    positionedToastBuilder: (context, child, gravity) {
      return Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 50.0,
        left: 0.0,
        right: 0.0,
        child: child,
      );
    },
  );
}
