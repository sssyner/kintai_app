import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kintai_app/models/employee.dart';

class EmployeeAvatar extends StatelessWidget {
  final Employee? employee;
  final String? photoUrl;
  final String? name;
  final double radius;

  const EmployeeAvatar({
    super.key,
    this.employee,
    this.photoUrl,
    this.name,
    this.radius = 20,
  });

  Widget _fallback(String displayName) {
    return CircleAvatar(
      radius: radius,
      child: Text(
        displayName.isNotEmpty ? displayName.substring(0, 1) : '?',
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl ?? employee?.photoUrl;
    final displayName = name ?? employee?.name ?? '';

    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          child: SizedBox(
            width: radius,
            height: radius,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _fallback(displayName),
      );
    }

    return _fallback(displayName);
  }
}
