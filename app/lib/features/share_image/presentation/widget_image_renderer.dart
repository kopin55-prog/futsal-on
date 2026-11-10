import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../team/presentation/team_logo.dart';

/// 화면에 띄우지 않은 위젯을 PNG 그림으로 만든다 (공유 이미지, 스프린트 03 6단계).
///
/// 화면 트리와 따로 그리는 작은 트리를 만들어 RepaintBoundary 를 그림으로 바꾼다. 새 라이브러리 없음.
/// - 너비는 [width] 로 고정, 높이는 내용만큼(최대 [maxHeight]).
/// - 로고 사진은 [context] 의 로고 불러오기([TeamLogoImages])로 먼저 받아 둔다. 못 받으면 글자 로고가 그려진다.
abstract final class WidgetImageRenderer {
  static const double maxHeight = 6000;

  /// 로고 사진을 기다리는 최대 시간. 넘으면 글자 로고로 그린다.
  static const Duration logoTimeout = Duration(seconds: 5);

  static Future<Uint8List> toPng(
    BuildContext context,
    Widget widget, {
    required double width,
    required double pixelRatio,
    String? logoImagePath,
  }) async {
    final view = View.of(context);
    final resolve = context.getInheritedWidgetOfExactType<TeamLogoImages>()?.resolve;
    if (logoImagePath != null && resolve != null) {
      final provider = resolve(logoImagePath);
      if (provider != null) {
        try {
          await precacheImage(provider, context, onError: (_, _) {}).timeout(logoTimeout);
        } on TimeoutException {
          // 글자 로고로 그린다
        }
      }
    }

    Widget tree = widget;
    if (resolve != null) tree = TeamLogoImages(resolve: resolve, child: tree);

    final boundary = RenderRepaintBoundary();
    final constraints = BoxConstraints(minWidth: width, maxWidth: width, maxHeight: maxHeight);
    final renderView = RenderView(
      view: view,
      child: boundary,
      configuration: ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints * pixelRatio,
        devicePixelRatio: 1,
      ),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: tree).attachToRenderTree(buildOwner);
    try {
      // 받아 둔 로고 사진처럼 그리는 중에 바로 준비되는 것이 있으면 한 번 더 짓는다.
      buildOwner
        ..buildScope(root)
        ..buildScope(root)
        ..finalizeTree();
      pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('png encode failed');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      // 그림을 만든 뒤 작은 트리를 치운다 (이미지 불러오기 구독 등 정리).
      RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(buildOwner, root);
      buildOwner
        ..buildScope(root)
        ..finalizeTree();
      pipelineOwner.rootNode = null;
    }
  }
}
