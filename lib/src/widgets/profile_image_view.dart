import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../base/utils/constants/color_constant.dart';

class ProfileImageView extends StatelessWidget {
  final String imageUrl;
  final double size;

  const ProfileImageView({
    super.key,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => Container(),
          progressIndicatorBuilder: (context, url, progress) =>
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
        ),
      ),
    );
  }
}
