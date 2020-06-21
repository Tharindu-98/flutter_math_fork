import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tuple/tuple.dart';

import '../../font/metrics/font_metrics.dart';
import '../../parser/tex_parser/types.dart';
import '../../render/constants.dart';
import '../../render/layout/custom_layout.dart';
import '../../render/svg/svg_geomertry.dart';
import '../../render/svg/svg_string_from_path.dart';
import '../../render/utils/render_box_offset.dart';
import '../../utils/iterable_extensions.dart';
import '../../utils/unicode_literal.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

/// Word:   \sqrt   \sqrt(index & base)
/// Latex:  \sqrt   \sqrt[index]{base}
/// MathML: msqrt   mroot

class SqrtNode extends SlotableNode {
  final EquationRowNode index;
  final EquationRowNode base;
  SqrtNode({
    @required this.index,
    @required this.base,
  }) : assert(base != null);

  SqrtNode copyWith({
    EquationRowNode index,
    EquationRowNode base,
  }) =>
      SqrtNode(
        index: index ?? this.index,
        base: base ?? this.base,
      );

  @override
  List<BuildResult> buildWidget(
          Options options, List<List<BuildResult>> childBuildResults) =>
      [
        BuildResult(
          options: options,
          widget: CustomLayout<_SqrtPos>(
            delegate: SqrtLayoutDelegate(
              options: options,
              baseOptions: childBuildResults[1][0].options,
              indexOptions: childBuildResults[0]?.firstOrNull?.options,
            ),
            children: <Widget>[
              CustomLayoutId(
                  id: _SqrtPos.base, child: childBuildResults[1][0].widget),
              if (index != null)
                CustomLayoutId(
                    id: _SqrtPos.ind, child: childBuildResults[0][0].widget),
            ],
          ),
          italic: Measurement.zero,
        )
      ];

  @override
  List<Options> computeChildOptions(Options options) => [
        options.havingStyle(MathStyle.scriptscript),
        options.havingStyle(options.style.cramp()),
      ];

  @override
  List<EquationRowNode> computeChildren() => [index, base];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(Options oldOptions, Options newOptions) => false;

  @override
  ParentableNode<EquationRowNode> updateChildren(
          List<EquationRowNode> newChildren) =>
      this.copyWith(index: newChildren[0], base: newChildren[1]);
}

enum _SqrtPos {
  base,
  ind, // Name collision here
}

// Square roots are handled in the TeXbook pg. 443, Rule 11.
class SqrtLayoutDelegate extends CustomLayoutDelegate<_SqrtPos> {
  final Options options;
  final Options baseOptions;
  final Options indexOptions;

  SqrtLayoutDelegate({
    @required this.options,
    @required this.baseOptions,
    @required this.indexOptions,
  });
  var heightAboveBaseline = 0.0;
  var svgHorizontalPos = 0.0;
  var svgVerticalPos = 0.0;
  DrawableRoot svgRoot;

  @override
  double computeDistanceToActualBaseline(
          TextBaseline baseline, Map<_SqrtPos, RenderBox> childrenTable) =>
      heightAboveBaseline;

  @override
  double getIntrinsicSize({
    Axis sizingDirection,
    bool max,
    double extent,
    double Function(RenderBox child, double extent) childSize,
    Map<_SqrtPos, RenderBox> childrenTable,
  }) {
    final base = childrenTable[_SqrtPos.base];
    final index = childrenTable[_SqrtPos.ind];

    throw UnimplementedError();
  }

  @override
  Size performLayout(BoxConstraints constraints,
      Map<_SqrtPos, RenderBox> childrenTable, RenderBox renderBox) {
    final base = childrenTable[_SqrtPos.base];
    final index = childrenTable[_SqrtPos.ind];

    childrenTable.forEach((key, value) {
      value.layout(infiniteConstraint, parentUsesSize: true);
    });

    final baseHeight = base.layoutHeight;
    final baseDepth = base.layoutDepth;
    final baseWidth = base.size.width;
    final indexHeight = index?.layoutHeight ?? 0.0;
    final indexWidth = index?.size?.width ?? 0.0;

    final theta = baseOptions.fontMetrics.defaultRuleThickness.cssEm
        .toLpUnder(baseOptions);
    var phi = baseOptions.style > MathStyle.text
        ? baseOptions.fontMetrics.xHeight.cssEm.toLpUnder(baseOptions)
        : theta;
    var psi = theta + 0.25 * phi.abs();

    final minSqrtHeight = base.size.height + psi + theta;

    // Pick sqrt svg
    final buildRes = sqrtImage(minSqrtHeight, baseWidth, options);

    // THIS IS A HACK. flutter_svg parses string asynchronously. However we can
    // only get the string during the rendering phase.
    svgRoot = null;
    buildRes.img.then((value) {
      svgRoot = value;
      renderBox.markNeedsPaint();
    });

    // Parameters for index
    // from KaTeX/src/katex.less
    final indexRightPadding = -10.0.mu.toLpUnder(options);
    // KaTeX chose a way to large value (5mu). We will use a smaller one.
    final indexLeftPadding = 0.5.pt.toLpUnder(options);
    final indexShift = 0.6 * (baseHeight - baseDepth);

    // Horizontal layout
    final sqrtHorizontalPos =
        math.max(0.0, indexLeftPadding + indexWidth - indexRightPadding);
    final width = sqrtHorizontalPos + buildRes.advanceWidth + baseWidth;
    svgHorizontalPos = sqrtHorizontalPos;

    // Vertical layout
    final delimDepth = buildRes.texHeight - buildRes.ruleWidth;
    if (delimDepth > base.size.height + psi) {
      psi += 0.5 * (delimDepth - base.size.height - psi);
    }
    final sqrtVerticalPos = math.max(
        0.0, indexHeight + indexShift - baseHeight - psi - buildRes.ruleWidth);
    svgVerticalPos = sqrtVerticalPos + buildRes.texHeight - buildRes.fullHeight;
    heightAboveBaseline =
        baseHeight + psi + buildRes.ruleWidth + sqrtVerticalPos;
    final fullHeight = sqrtVerticalPos + buildRes.texHeight;

    base.offset = Offset(sqrtHorizontalPos + buildRes.advanceWidth,
        heightAboveBaseline - baseHeight);
    index?.offset = Offset(sqrtHorizontalPos - indexRightPadding - indexWidth,
        heightAboveBaseline - indexShift - indexHeight);

    return Size(width, fullHeight);
  }

  @override
  void additionalPaint(PaintingContext context, Offset offset) {
    if (svgRoot != null) {
      final canvas = context.canvas;
      canvas.translate(
          offset.dx + svgHorizontalPos, offset.dy + svgVerticalPos);
      canvas.scale(
        svgRoot.viewport.width / svgRoot.viewport.viewBox.width,
        svgRoot.viewport.height / svgRoot.viewport.viewBox.height,
      );
      canvas.clipRect(Rect.fromLTWH(0.0, 0.0, svgRoot.viewport.viewBox.width,
          svgRoot.viewport.viewBox.height));
      // canvas.drawRect(
      //     Rect.fromLTWH(0.0, 0.0, svgRoot.viewport.viewBox.width,
      //         svgRoot.viewport.viewBox.height),
      //     Paint()
      //       ..style = PaintingStyle.fill
      //       ..color = Colors.blue
      //       ..strokeWidth = 1);
      svgRoot.draw(canvas, null);
    }
  }
}

class _SqrtSvgRes {
  final Future<DrawableRoot> img;
  final double ruleWidth;
  final double advanceWidth;
  final double fullHeight;
  final double texHeight;
  const _SqrtSvgRes({
    @required this.img,
    @required this.ruleWidth,
    @required this.advanceWidth,
    @required this.fullHeight,
    @required this.texHeight,
  });
}

const stackLargeDelimieterSequence = [
  // Tuple2('Main-Regular', MathStyle.scriptscript),
  // Tuple2('Main-Regular', MathStyle.script),
  Tuple2('Main-Regular', MathStyle.text),
  Tuple2('Size1-Regular', MathStyle.text),
  Tuple2('Size2-Regular', MathStyle.text),
  Tuple2('Size3-Regular', MathStyle.text),
  Tuple2('Size4-Regular', MathStyle.text),
];

double getHeightForDelim({
  String delim,
  String fontName,
  MathStyle style,
  Options options,
}) {
  final metrics = getCharacterMetrics(
      character: delim, fontName: fontName, mode: Mode.math);
  if (metrics == null) {
    throw StateError('Illegal delimiter char $delim'
        '(${unicodeLiteral(delim)}) appeared in AST');
  }
  final fullHeight = metrics.height + metrics.depth;
  final newOptions = options.havingStyle(style);
  return fullHeight.cssEm.toLpUnder(newOptions);
}

const vbPad = 80;
const emPad = vbPad / 1000;

// We use a different strategy of picking \\surd font than KaTeX
// KaTeX chooses the style and font of the \\surd to cover inner at *normalsize*
// We will use a highly similar strategy while sticking to the strict meaning
// of TexBook Rule 11. We do not choose the style at *normalsize*
_SqrtSvgRes sqrtImage(
    double minDelimiterHeight, double baseWidth, Options options) {
  // final newOptions = options.havingBaseSize();
  final delimConf = stackLargeDelimieterSequence.firstWhere(
    (element) =>
        getHeightForDelim(
          delim: '\u221A', // √
          fontName: element.item1,
          style: element.item2,
          options: options,
        ) >
        minDelimiterHeight,
  );

  final extraViniculum = 0.0; //math.max(0.0, options)
  final ruleWidth =
      options.fontMetrics.sqrtRuleThickness.cssEm.toLpUnder(options);
  // TODO: support Settings.minRuleThickness.

  // These are the known height + depth for \u221A
  if (delimConf != null) {
    final fontHeight = const {
      'Main-Regular': 1.0,
      'Size1-Regular': 1.2,
      'Size2-Regular': 1.8,
      'Size3-Regular': 2.4,
      'Size4-Regular': 3.0,
    }[delimConf.item1];
    final delimOptions = options.havingStyle(delimConf.item2);
    final viewPortHeight =
        (fontHeight + extraViniculum + emPad).cssEm.toLpUnder(delimOptions);
    final texHeight =
        (fontHeight + extraViniculum).cssEm.toLpUnder(delimOptions);
    if (delimConf?.item1 == 'Main-Regular') {
      // We will be vertically stretching the sqrtMain path (by viewPort vs
      // viewBox) to mimic the height of \u221A under Main-Regular font and
      // corresponding Mathstyle.

      // final advanceWidth = 0.833.cssEm.toLpUnder(options);
      // final viewPortWidth = advanceWidth + baseWidth;
      // final viewBoxHeight = 1000 + 1000 * extraViniculum + vbPad;
      // final viewBoxWidth = viewPortWidth.lp.toCssEmUnder(options) * 1000;
      final advanceWidth = 0.833.cssEm.toLpUnder(delimOptions);
      final viewPortWidth = advanceWidth + baseWidth;
      final viewBoxHeight = 1000 + 1000 * extraViniculum + vbPad;
      final viewBoxWidth = viewPortWidth.lp.toCssEmUnder(delimOptions) * 1000;
      final svgPath = sqrtPath('sqrtMain', extraViniculum, viewBoxHeight);
      final svgString = svgStringFromPath(
        svgPath,
        [viewPortWidth, viewPortHeight],
        [0, 0, viewBoxWidth, viewBoxHeight],
      );
      return _SqrtSvgRes(
        img: svg.fromSvgString(svgString, svgString),
        ruleWidth: (options.fontMetrics.sqrtRuleThickness + extraViniculum)
            .cssEm
            .toLpUnder(delimOptions),
        advanceWidth: advanceWidth,
        fullHeight: viewPortHeight,
        texHeight: texHeight,
      );
    } else {
      // We will directly apply corresponding font

      final advanceWidth = 1.0.cssEm.toLpUnder(delimOptions);
      final viewPortWidth = math.max(
        advanceWidth + baseWidth,
        1.02.cssEm.toCssEmUnder(delimOptions),
      );
      final viewBoxHeight = (1000 + vbPad) * fontHeight;
      final viewBoxWidth = viewPortWidth.lp.toCssEmUnder(delimOptions) * 1000;
      final svgPath = sqrtPath('sqrt${delimConf.item1.substring(0, 5)}',
          extraViniculum, viewBoxHeight);
      final svgString = svgStringFromPath(
        svgPath,
        [viewPortWidth, viewPortHeight],
        [0, 0, viewBoxWidth, viewBoxHeight],
      );
      return _SqrtSvgRes(
        img: svg.fromSvgString(svgString, svgString),
        ruleWidth: (options.fontMetrics.sqrtRuleThickness + extraViniculum)
            .cssEm
            .toLpUnder(delimOptions),
        advanceWidth: advanceWidth,
        fullHeight: viewPortHeight,
        texHeight: texHeight,
      );
    }
  } else {
    // We will use the viewBoxHeight parameter in sqrtTall path
    final viewPortHeight =
        minDelimiterHeight + (extraViniculum + emPad).cssEm.toLpUnder(options);
    final texHeight =
        minDelimiterHeight + extraViniculum.cssEm.toLpUnder(options);
    final viewBoxHeight = 1000 * minDelimiterHeight.lp.toCssEmUnder(options) +
        extraViniculum +
        vbPad;
    final advanceWidth = 1.056.cssEm.toLpUnder(options);
    final viewPortWidth = advanceWidth + baseWidth;
    final viewBoxWidth = viewPortWidth.lp.toCssEmUnder(options) * 1000;
    final svgPath = sqrtPath('sqrt${delimConf.item1.substring(0, 5)}',
        extraViniculum, viewBoxHeight);
    final svgString = svgStringFromPath(
      svgPath,
      [viewPortWidth, viewPortHeight],
      [0, 0, viewBoxWidth, viewBoxHeight],
    );
    return _SqrtSvgRes(
      img: svg.fromSvgString(svgString, svgString),
      ruleWidth: (options.fontMetrics.sqrtRuleThickness + extraViniculum)
          .cssEm
          .toLpUnder(options),
      advanceWidth: advanceWidth,
      fullHeight: viewPortHeight,
      texHeight: texHeight,
    );
  }
}
