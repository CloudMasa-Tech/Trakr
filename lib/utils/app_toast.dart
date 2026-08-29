import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class AppToast {
  static void showSuccess(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.success,
      style: ToastificationStyle.flatColored,
      title: Text(message),
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 4),
      backgroundColor: Colors.green.shade600,
      foregroundColor: Colors.white,
      showProgressBar: false,
      margin: const EdgeInsets.only(bottom: 24),
    );
  }

  static void showError(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      style: ToastificationStyle.flatColored,
      title: Text(message),
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 4),
      backgroundColor: Colors.red.shade600,
      foregroundColor: Colors.white,
      showProgressBar: false,
      margin: const EdgeInsets.only(bottom: 24),
    );
  }

  static void showInfo(BuildContext context, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flatColored,
      title: Text(message),
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 4),
      showProgressBar: false,
      margin: const EdgeInsets.only(bottom: 24),
    );
  }

  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final bg = snackBar.backgroundColor;
    bool isError = false;
    bool isSuccess = false;
    if (bg != null) {
      if (bg == Colors.red || bg == Colors.red.shade600 || bg == Colors.redAccent) isError = true;
      if (bg == Colors.green || bg == Colors.green.shade600) isSuccess = true;
    }
    
    toastification.show(
      context: context,
      type: isError ? ToastificationType.error : isSuccess ? ToastificationType.success : ToastificationType.info,
      style: ToastificationStyle.flatColored,
      title: snackBar.content,
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 4),
      backgroundColor: bg,
      foregroundColor: bg != null ? Colors.white : null,
      showProgressBar: false,
      margin: const EdgeInsets.only(bottom: 24),
    );
  }
}
