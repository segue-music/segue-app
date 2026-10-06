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
    this.leading,
    super.key,
  });

  final String text;

  /// Where it goes ("Abrir o artista").
  final String tooltip;

  final VoidCallback? onTap;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  /// What goes before the text, in the link: an artist's picture, before their name.
  final Widget? leading;

  @override
  State<TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<TextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      style: _hovered && widget.onTap != null
          ? (widget.style ?? const TextStyle()).copyWith(decoration: TextDecoration.underline)
          : widget.style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
    );
    final leading = widget.leading;
    final link = InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: widget.onTap,
      onHover: (hovered) => setState(() => _hovered = hovered),
      hoverColor: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: leading == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 8),
                Flexible(child: text),
              ],
            ),
    );

    // Only as wide as its text (and what goes before it), also where a line stretches it (a song's artist in a list tile): the rest
    // of that line, under the mouse or the finger, belongs to what holds it. Where nothing stretches it,
    // it takes no more room than its text, leaving the rest to what follows it (an album's year).
    return Align(
      alignment: widget.textAlign == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: widget.onTap == null ? link : Tooltip(message: widget.tooltip, child: link),
    );
  }
}
