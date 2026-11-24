import 'package:flutter/material.dart';
import '../theme.dart';

/// Loads data, shows spinner/error/empty, supports pull-to-refresh.
class AsyncList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback reload) row;
  final String empty;
  final Widget? header;
  final GlobalKey<AsyncListState>? listKey;
  const AsyncList({
    super.key,
    required this.load,
    required this.row,
    this.empty = 'Nothing here yet.',
    this.header,
    this.listKey,
  });
  @override
  State<AsyncList> createState() => AsyncListState();
}

class AsyncListState extends State<AsyncList> {
  late Future<List<Map<String, dynamic>>> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  void reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${s.error}'),
            TextButton(onPressed: reload, child: const Text('Retry'))
          ]));
        }
        final data = s.data ?? [];
        return RefreshIndicator(
          onRefresh: () async {
            reload();
            await _f;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (widget.header != null) widget.header!,
              if (data.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(widget.empty))),
              for (var k = 0; k < data.length; k++)
                FadeIn(
                    index: k,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: widget.row(c, data[k], reload))),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}

Future<Map<String, String>?> askFields(
    BuildContext context, String title, List<String> fields) {
  final ctrls = {for (final f in fields) f: TextEditingController()};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in fields)
            TextField(controller: ctrls[f], decoration: InputDecoration(labelText: f)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, {for (final f in fields) f: ctrls[f]!.text.trim()}),
            child: const Text('Save')),
      ],
    ),
  );
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String shortDate(dynamic v) {
  if (v == null) return '';
  final s = '$v';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

/// Asks before anything is deleted.
Future<bool> confirmDelete(BuildContext context, String what) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Delete?'),
      content: Text('Delete $what? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD64545), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete')),
      ],
    ),
  );
  return r == true;
}

/// Fades and slides its child in; `index` staggers a list.
class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) {
    final ms = 320 + (index > 8 ? 8 : index) * 55;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) =>
          Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c)),
      child: child,
    );
  }
}

/// White (or dark-mode) rounded card.
class GCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const GCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(28)),
      child: child);
}

/// Pastel block. Text and icons inside stay dark so they read in light and dark mode.
class Pastel extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool expand;
  const Pastel(
      {super.key,
      required this.color,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.radius = 28,
      this.expand = true});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expand ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: DefaultTextStyle.merge(
          style: const TextStyle(color: C.dark),
          child: IconTheme.merge(data: const IconThemeData(color: C.dark), child: child)));
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        if (action != null)
          GestureDetector(
              onTap: onAction, child: Text(action!, style: TextStyle(fontSize: 13, color: context.muted))),
      ]));
}

/// Round icon button, like the bell / back buttons in the design.
class RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const RoundBtn(this.icon, {super.key, this.onTap, this.size = 46});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(color: context.cardBg, shape: BoxShape.circle, boxShadow: const [
            BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))
          ]),
          child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(icon, key: ValueKey(icon), color: context.ink, size: size * 0.45))));
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context) => RoundBtn(
      context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      onTap: () => ThemeController.toggle(context));
}

/// Small coloured pill label.
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Tag(this.text, {super.key, this.color = Colors.white, this.icon});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: C.dark), const SizedBox(width: 6)],
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.dark)),
      ]));
}

/// Half-circle gauge; the arc grows in when it appears.
class Gauge extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  const Gauge({super.key, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final track = context.isDark ? const Color(0xFF34343A) : const Color(0xFFE6E6EA);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => CustomPaint(size: const Size(84, 46), painter: _GaugePainter(v, color, track)),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double v;
  final Color color;
  final Color track;
  _GaugePainter(this.v, this.color, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.width - 12);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = track;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, 3.14159265, 3.14159265, false, bg);
    if (v > 0) canvas.drawArc(rect, 3.14159265, 3.14159265 * v, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.v != v || o.color != color || o.track != track;
}
