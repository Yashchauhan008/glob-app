import 'package:flutter/material.dart';

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
              for (final r in data) widget.row(c, r, reload),
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
