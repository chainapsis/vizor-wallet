import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// iOS continuous corners; other hosts retain their circular modal outline.
ShapeBorder appModalShape(BorderRadius borderRadius) =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? RoundedSuperellipseBorder(borderRadius: borderRadius)
    : RoundedRectangleBorder(borderRadius: borderRadius);
