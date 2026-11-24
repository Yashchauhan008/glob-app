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
              for (final r in data)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: widget.row(c, r, reload)),
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

/// White rounded card.
class GCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  const GCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
      child: child);
}

/// Big yellow rounded panel that holds white cards.
class Panel extends StatelessWidget {
  final Widget child;
  final Color color;
  const Panel({super.key, required this.child, this.color = C.blue});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
      child: child);
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
              onTap: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 13, color: C.muted))),
      ]));
}

/// Round white icon button, like the bell / back buttons in the design.
class RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color iconColor;
  final double size;
  const RoundBtn(this.icon,
      {super.key, this.onTap, this.color = Colors.white, this.iconColor = C.ink, this.size = 46});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: const [
            BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))
          ]),
          child: Icon(icon, color: iconColor, size: size * 0.45)));
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
        if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 6)],
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]));
}

/// Half-circle gauge with a percentage inside the arc.
class Gauge extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  const Gauge({super.key, required this.value, required this.color});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(84, 46), painter: _GaugePainter(value.clamp(0, 1).toDouble(), color));
}

class _GaugePainter extends CustomPainter {
  final double v;
  final Color color;
  _GaugePainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.width - 12);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE6E6EA);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, 3.14159265, 3.14159265, false, bg);
    if (v > 0) canvas.drawArc(rect, 3.14159265, 3.14159265 * v, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.v != v || o.color != color;
}
