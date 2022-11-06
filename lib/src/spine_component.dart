import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_spine/flame_spine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:spine_core/spine_core.dart' as core;

abstract class SpineComponent extends PositionComponent {
  //#region Define variable
  SkeletonAnimation? _skeleton;
  final String? asset;
  final core.Color _tempColor = core.Color();
  static const int vertexSize = 2 + 2 + 4;
  static const List<int> quadTriangles = <int>[0, 1, 2, 2, 3, 0];

  /// How many steps we will use for calculate a render size by [animation].
  static const int countStepsForCalculateBounds = 100;

  /// A start animation. We will use it for calculate bounds by frames.
  String? _animation;
  bool _debugRendering = false;
  bool triangleRendering;
  Paint? defaultPaint;
  double globalAlpha = 1.0;
  double frameSizeMultiplier;
  core.Bounds? bounds;
  Alignment? alignment;
  BoxFit? fit;
  Float32List _vertices = Float32List(8 * 1024);

  @mustCallSuper
  SpineComponent({
    SkeletonAnimation? skeleton,
    String? animation,
    this.triangleRendering = true,
    this.frameSizeMultiplier = 0.0,
    this.alignment,
    this.fit,
    this.asset,
  }) {
    assert(skeleton != null || asset != null, 'Provide animation');

    _skeleton = skeleton;
    this.animation = animation;
  }

  //#endregion

  //#region Get/Set
  SkeletonAnimation get skeleton => _skeleton!;

  bool get debugRendering => _debugRendering;

  set debugRendering(debug) => _debugRendering = debug;

  /// A start animation. We will use it for calculate bounds by frames.
  String? get animation {
    if (_animation != null) return _animation;
    if (skeleton.data.animations.isNotEmpty) {
      return skeleton.data.animations.first.name;
    }
    return null;
  }

  set animation(String? value) {
    if (_animation == value) return;
    _animation = value;
    if (_skeleton != null && animation != null) {
      skeleton.state.setAnimation(0, animation!, true);
      bounds = _calculateBounds();
    }
  }

  //#endregion

  @override
  @mustCallSuper
  Future<void> onLoad() async {
    _skeleton ??= await _loadSkeleton();
    animation ??= (await _loadAnimations()).last;
    skeleton.state.setAnimation(0, animation!, true);

    final bounds = calculateBoundsByAnimation();
    size = Vector2(bounds.size.x, bounds.size.y);
  }

  String get name => asset?.split('/').last.split('.').first ?? '';

  String get path => asset?.replaceAll('$name.json', '') ?? '';

  Future<SkeletonAnimation> _loadSkeleton() async {
    return SkeletonAnimation.createWithFiles(name, pathBase: path);
  }

  Future<Set<String>> _loadAnimations() async {
    final String skeletonFile = '$name.json';
    final String s = await rootBundle.loadString('$path$skeletonFile');
    final Map<String, dynamic> data = jsonDecode(s);
    final animations = (data['animations'] ?? {}).keys.toSet();
    log('$name: $animations', name: 'ANIMATION');
    return animations;
  }

  @override
  @mustCallSuper
  void update(double dt) async {
    skeleton
      ..updateState(dt)
      ..applyState()
      ..updateWorldTransform();
  }

  @override
  @mustCallSuper
  void render(Canvas canvas) async {
    triangleRendering
        ? _drawTriangles(canvas, skeleton)
        : _drawImages(canvas, skeleton);
  }

  Paint _buildPaint() {
    final Paint p = defaultPaint ?? Paint()
      ..isAntiAlias = true;
    return p..color = p.color.withOpacity(globalAlpha);
  }

  core.Bounds _calculateBounds() {
    late final core.Bounds bounds;
    if (_animation == null) {
      skeleton
        ..setToSetupPose()
        ..updateWorldTransform();
      final core.Vector2 offset = core.Vector2();
      final core.Vector2 size = core.Vector2();
      skeleton.getBounds(offset, size, <double>[]);
      bounds = core.Bounds(offset, size);
    } else {
      bounds = calculateBoundsByAnimation();
    }

    final core.Vector2 delta = core.Vector2(
      bounds.size.x * frameSizeMultiplier,
      bounds.size.y * frameSizeMultiplier,
    );

    return core.Bounds(
      core.Vector2(
        bounds.offset.x - delta.x / 2,
        bounds.offset.y - delta.y / 2,
      ),
      core.Vector2(
        bounds.size.x + delta.x,
        bounds.size.y + delta.y,
      ),
    );
  }

  /// \thanks https://github.com/EsotericSoftware/spine-runtimes/blob/3.7/spine-ts/player/src/Player.ts#L1169
  core.Bounds calculateBoundsByAnimation() {
    final core.Vector2 offset = core.Vector2();
    final core.Vector2 size = core.Vector2();
    if (animation == null) {
      return core.Bounds(offset, size);
    }

    final core.Animation? skeletonAnimation =
        skeleton.data.findAnimation(animation!);
    if (skeletonAnimation == null) {
      return core.Bounds(offset, size);
    }

    skeleton.state.clearTracks();
    skeleton
      ..setToSetupPose()
      ..updateWorldTransform();
    skeleton.state.setAnimationWith(0, skeletonAnimation, true);

    final double stepTime = skeletonAnimation.duration > 0.0
        ? skeletonAnimation.duration / countStepsForCalculateBounds
        : 0.0;
    double minX = double.maxFinite;
    double maxX = -double.maxFinite;
    double minY = double.maxFinite;
    double maxY = -double.maxFinite;

    for (int i = 0; i < countStepsForCalculateBounds; ++i) {
      skeleton.state
        ..update(stepTime)
        ..apply(skeleton);
      skeleton
        ..updateWorldTransform()
        ..getBounds(offset, size, <double>[]);

      minX = math.min(offset.x, minX);
      maxX = math.max(offset.x + size.x, maxX);
      minY = math.min(offset.y, minY);
      maxY = math.max(offset.y + size.y, maxY);
    }

    offset
      ..x = minX
      ..y = minY;
    size
      ..x = maxX - minX
      ..y = maxY - minY;

    return core.Bounds(offset, size);
  }

  Float32List _computeRegionVertices(
      core.Slot slot, core.RegionAttachment region, bool pma) {
    final core.Skeleton skeleton = slot.bone.skeleton;
    final core.Color skeletonColor = skeleton.color;
    final core.Color slotColor = slot.color;
    final core.Color regionColor = region.color;
    final double alpha = skeletonColor.a * slotColor.a * regionColor.a;
    final double multiplier = pma ? alpha : 1.0;
    final core.Color color = _tempColor
      ..set(
          skeletonColor.r * slotColor.r * regionColor.r * multiplier,
          skeletonColor.g * slotColor.g * regionColor.g * multiplier,
          skeletonColor.b * slotColor.b * regionColor.b * multiplier,
          alpha);

    region.computeWorldVertices2(slot.bone, _vertices, 0, vertexSize);

    final Float32List vertices = _vertices;
    final Float32List uvs = region.uvs;

    vertices[core.RegionAttachment.c1r] = color.r;
    vertices[core.RegionAttachment.c1g] = color.g;
    vertices[core.RegionAttachment.c1b] = color.b;
    vertices[core.RegionAttachment.c1a] = color.a;
    vertices[core.RegionAttachment.u1] = uvs[0];
    vertices[core.RegionAttachment.v1] = uvs[1];

    vertices[core.RegionAttachment.c2r] = color.r;
    vertices[core.RegionAttachment.c2g] = color.g;
    vertices[core.RegionAttachment.c2b] = color.b;
    vertices[core.RegionAttachment.c2a] = color.a;
    vertices[core.RegionAttachment.u2] = uvs[2];
    vertices[core.RegionAttachment.v2] = uvs[3];

    vertices[core.RegionAttachment.c3r] = color.r;
    vertices[core.RegionAttachment.c3g] = color.g;
    vertices[core.RegionAttachment.c3b] = color.b;
    vertices[core.RegionAttachment.c3a] = color.a;
    vertices[core.RegionAttachment.u3] = uvs[4];
    vertices[core.RegionAttachment.v3] = uvs[5];

    vertices[core.RegionAttachment.c4r] = color.r;
    vertices[core.RegionAttachment.c4g] = color.g;
    vertices[core.RegionAttachment.c4b] = color.b;
    vertices[core.RegionAttachment.c4a] = color.a;
    vertices[core.RegionAttachment.u4] = uvs[6];
    vertices[core.RegionAttachment.v4] = uvs[7];

    return vertices;
  }

  Float32List _computeMeshVertices(
      core.Slot slot, core.MeshAttachment mesh, bool pma) {
    final core.Skeleton skeleton = slot.bone.skeleton;
    final core.Color skeletonColor = skeleton.color;
    final core.Color slotColor = slot.color;
    final core.Color regionColor = mesh.color;
    final double alpha = skeletonColor.a * slotColor.a * regionColor.a;
    final double multiplier = pma ? alpha : 1;
    final core.Color color = _tempColor
      ..set(
          skeletonColor.r * slotColor.r * regionColor.r * multiplier,
          skeletonColor.g * slotColor.g * regionColor.g * multiplier,
          skeletonColor.b * slotColor.b * regionColor.b * multiplier,
          alpha);

    final int numVertices = mesh.worldVerticesLength ~/ 2;
    if (_vertices.length < mesh.worldVerticesLength) {
      _vertices = Float32List(mesh.worldVerticesLength);
    }
    final Float32List vertices = _vertices;
    mesh.computeWorldVertices(
        slot, 0, mesh.worldVerticesLength, vertices, 0, vertexSize);

    final Float32List uvs = mesh.uvs!;
    final int n = numVertices;
    for (int i = 0, u = 0, v = 2; i < n; i++) {
      vertices[v++] = color.r;
      vertices[v++] = color.g;
      vertices[v++] = color.b;
      vertices[v++] = color.a;
      vertices[v++] = uvs[u++];
      vertices[v++] = uvs[u++];
      v += 2;
    }

    return vertices;
  }

  //#region Draw
  void _drawImages(Canvas canvas, SkeletonAnimation skeleton) {
    final Paint paint = Paint();
    final List<core.Slot> drawOrder = skeleton.drawOrder;

    canvas.save();

    final int n = drawOrder.length;

    for (int i = 0; i < n; i++) {
      final core.Slot slot = drawOrder[i];
      final core.Attachment attachment = slot.getAttachment()!;
      core.RegionAttachment regionAttachment;
      core.TextureAtlasRegion region;
      Image image;

      if (attachment is! core.RegionAttachment) {
        continue;
      }

      regionAttachment = attachment;
      region = regionAttachment.region as core.TextureAtlasRegion;
      image = region.texture?.image;

      final core.Skeleton skeleton = slot.bone.skeleton;
      final core.Color skeletonColor = skeleton.color;
      final core.Color slotColor = slot.color;
      final core.Color regionColor = regionAttachment.color;
      final double alpha = skeletonColor.a * slotColor.a * regionColor.a;
      final core.Color color = _tempColor
        ..set(
            skeletonColor.r * slotColor.r * regionColor.r,
            skeletonColor.g * slotColor.g * regionColor.g,
            skeletonColor.b * slotColor.b * regionColor.b,
            alpha);

      final core.Bone bone = slot.bone;
      double w = region.width.toDouble();
      double h = region.height.toDouble();

      canvas
        ..save()
        ..transform(Float64List.fromList(<double>[
          bone.a,
          bone.c,
          0.0,
          0.0,
          bone.b,
          bone.d,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
          bone.worldX,
          bone.worldY,
          0.0,
          1.0
        ]))
        ..translate(regionAttachment.offset[0], regionAttachment.offset[1])
        ..rotate((regionAttachment.rotation) * math.pi / 180);

      final double atlasScale = (regionAttachment.width) / w;

      canvas
        ..scale(atlasScale * (regionAttachment.scaleX),
            atlasScale * (regionAttachment.scaleY))
        ..translate(w / 2, h / 2);
      if (regionAttachment.region.rotate) {
        final double t = w;
        w = h;
        h = t;
        canvas.rotate(-math.pi / 2);
      }
      canvas
        ..scale(1.0, -1.0)
        ..translate(-w / 2, -h / 2);
      if (color.r != 1 || color.g != 1 || color.b != 1 || color.a != 1) {
        final int alpha = (color.a * 255).toInt();
        paint.color = paint.color.withAlpha(alpha);
      }
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(region.x.toDouble(), region.y.toDouble(), w, h),
          Rect.fromLTWH(0.0, 0.0, w, h),
          paint);
      if (debugRendering) {
        canvas.drawRect(Rect.fromLTWH(0.0, 0.0, w, h), paint);
      }
      canvas.restore();
    }

    canvas.restore();
  }

  void _drawTriangles(Canvas canvas, SkeletonAnimation skeleton) {
    core.BlendMode? blendMode;

    final List<core.Slot> drawOrder = skeleton.drawOrder;
    Float32List vertices = _vertices;
    List<int> triangles;

    final int n = drawOrder.length;
    for (int i = 0; i < n; i++) {
      final core.Slot slot = drawOrder[i];
      final core.Attachment? attachment = slot.getAttachment();
      if (attachment == null) {
        continue;
      }

      Image? texture;
      core.TextureAtlasRegion region;
      core.Color attachmentColor;
      if (attachment is core.RegionAttachment) {
        final core.RegionAttachment regionAttachment = attachment;
        vertices = _computeRegionVertices(slot, regionAttachment, false);
        triangles = quadTriangles;
        region = regionAttachment.region as core.TextureAtlasRegion;
        texture = region.texture?.image;
        attachmentColor = regionAttachment.color;
      } else if (attachment is core.MeshAttachment) {
        final core.MeshAttachment mesh = attachment;
        vertices = _computeMeshVertices(slot, mesh, false);
        triangles = mesh.triangles!;
        texture = mesh.region?.renderObject.texture.image;
        attachmentColor = mesh.color;
      } else {
        continue;
      }

      if (texture != null) {
        final core.BlendMode slotBlendMode = slot.data.blendMode!;
        if (slotBlendMode != blendMode) {
          blendMode = slotBlendMode;
        }

        final core.Skeleton skeleton = slot.bone.skeleton;
        final core.Color skeletonColor = skeleton.color;
        final core.Color slotColor = slot.color;
        final double alpha = skeletonColor.a * slotColor.a * attachmentColor.a;
        final core.Color color = _tempColor
          ..set(
              skeletonColor.r * slotColor.r * attachmentColor.r,
              skeletonColor.g * slotColor.g * attachmentColor.g,
              skeletonColor.b * slotColor.b * attachmentColor.b,
              alpha);

        globalAlpha = color.a;

        for (int j = 0; j < triangles.length; j += 3) {
          final int t1 = triangles[j] * 8,
              t2 = triangles[j + 1] * 8,
              t3 = triangles[j + 2] * 8;

          final double x0 = vertices[t1],
              y0 = vertices[t1 + 1],
              u0 = vertices[t1 + 6],
              v0 = vertices[t1 + 7];
          final double x1 = vertices[t2],
              y1 = vertices[t2 + 1],
              u1 = vertices[t2 + 6],
              v1 = vertices[t2 + 7];
          final double x2 = vertices[t3],
              y2 = vertices[t3 + 1],
              u2 = vertices[t3 + 6],
              v2 = vertices[t3 + 7];

          _drawTriangle(
              canvas, texture, x0, y0, u0, v0, x1, y1, u1, v1, x2, y2, u2, v2);

          if (debugRendering) {
            _drawDebug(x0, y0, x1, y1, x2, y2, canvas);
          }
        }
      }
    }
  }

  void _drawDebug(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    Canvas canvas,
  ) {
    final Path path = Path()
      ..moveTo(x0, y0)
      ..lineTo(x1, y1)
      ..lineTo(x2, y2)
      ..lineTo(x0, y0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF4CAF50)
        ..strokeWidth = 1,
    );
  }

  void _drawTriangle(
      Canvas canvas,
      Image img,
      double x0,
      double y0,
      double u0,
      double v0,
      double x1,
      double y1,
      double u1,
      double v1,
      double x2,
      double y2,
      double u2,
      double v2) {
    u0 *= img.width;
    v0 *= img.height;
    u1 *= img.width;
    v1 *= img.height;
    u2 *= img.width;
    v2 *= img.height;

    final Path path = Path()
      ..moveTo(x0, y0)
      ..lineTo(x1, y1)
      ..lineTo(x2, y2)
      ..close();

    x1 -= x0;
    y1 -= y0;
    x2 -= x0;
    y2 -= y0;

    u1 -= u0;
    v1 -= v0;
    u2 -= u0;
    v2 -= v0;

    final double det = 1 / (u1 * v2 - u2 * v1),
        // linear transformation
        a = (v2 * x1 - v1 * x2) * det,
        b = (v2 * y1 - v1 * y2) * det,
        c = (u1 * x2 - u2 * x1) * det,
        d = (u1 * y2 - u2 * y1) * det,
        // translation
        e = x0 - a * u0 - c * v0,
        f = y0 - b * u0 - d * v0;

    canvas
      ..save()
      ..clipPath(path, doAntiAlias: false)

      /*
        https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/transform
        http://www.opengl-tutorial.org/cn/beginners-tutorials/tutorial-3-matrices/
        a c 0 e
        b d 0 f
        0 0 1 0
        0 0 0 1
      */
      ..transform(
        Float64List.fromList(<double>[
          a,
          b,
          0.0,
          0.0,
          c,
          d,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0,
          0.0,
          e,
          f,
          0.0,
          1.0,
        ]),
      )
      ..drawImage(img, const Offset(0.0, 0.0), _buildPaint())
      ..restore();
  }

//#endregion

}
