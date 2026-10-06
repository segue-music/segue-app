import 'package:flutter/material.dart';

/// Text that opens something when tapped: underlined under the mouse, and tinted under the focus as
/// everything else is. Without [onTap] it is plain text, with no tooltip.
class TextLink extends StatefulWidget {
  const TextLink(
    this.text, {
    required this.tooltip,
    this.onTap,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    super.key,
  });

  final String text;

  /// Where it goes ("Abrir o artista").
  final String tooltip;

  final VoidCallback? onTap;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  State<TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<TextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final link = InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: widget.onTap,
      onHover: (hovered) => setState(() => _hovered = hovered),
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: Text(
        widget.text,
        style: _hovered && widget.onTap != null
            ? (widget.style ?? const TextStyle()).copyWith(decoration: TextDecoration.underline)
            : widget.style,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
      ),
    );

    if (widget.onTap == null) {
      return link;
    }

    return Tooltip(message: widget.tooltip, child: link);
  }
}
