import 'dart:io';

import 'package:flutter/material.dart';

/// Displays a durable profile URL, falling back to a legacy local avatar file.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.radius,
    this.imageUrl,
    this.localPath,
    this.backgroundColor,
    this.iconColor,
  });

  final double radius;
  final String? imageUrl;
  final String? localPath;
  final Color? backgroundColor;
  final Color? iconColor;

  ImageProvider<Object>? get _imageProvider {
    final url = imageUrl?.trim() ?? '';
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return NetworkImage(url);
    }

    final path = localPath?.trim() ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      return FileImage(File(path));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _imageProvider;
    final size = radius * 2;

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primary,
      child: provider == null
          ? Icon(Icons.person_rounded, color: iconColor ?? Colors.white, size: size * .56)
          : ClipOval(
              child: Image(
                image: provider,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person_rounded,
                  color: iconColor ?? Colors.white,
                  size: size * .56,
                ),
              ),
            ),
    );
  }
}
