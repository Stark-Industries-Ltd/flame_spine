import 'package:flame/experimental.dart';
import 'package:flame/game.dart';
import 'package:flame_spine/flame_spine.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(GameWidget(game: MyGame()));
}

class MyGame extends FlameGame
    with HasTappableComponents, HasCollisionDetection {
  late final RouterComponent router;

  @override
  Future<void> onLoad() async {
    add(
      GrassObject()
        ..position = size / 2
        ..angle = 3.14,
    );
  }
}

class GrassObject extends SpineComponent {
  GrassObject() : super(asset: 'assets/grass.json');
}
