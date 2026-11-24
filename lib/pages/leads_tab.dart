import 'package:flutter/material.dart';
import '../api.dart';
import 'common.dart';

class LeadsTab extends StatefulWidget {
  const LeadsTab({super.key});
  @override
  State<LeadsTab> createState() => _LeadsTabState();
}

class _LeadsTabState extends State<LeadsTab> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _add() async {
    final r = await askFields(context, 'New lead', ['Name', 'Email', 'Phone', 'Company']);
    if (r == null || r['Name']!.isEmpty) return;
    try {
      await Api.post('/leads', {
        'name': r['Name'],
        if (r['Email']!.isNotEmpty) 'email': r['Email'],
        if (r['Phone']!.isNotEmpty) 'phone': r['Phone'],
        if (r['Company']!.isNotEmpty) 'company': r['Company'],
      });
      _key.currentState?.reload();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncList(
        key: _key,
        load: () async => items(await Api.get('/leads')),
        empty: 'No leads yet.',
        row: (c, l, reload) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text('${l['name']}'),
          subtitle: Text([
            if (l['company'] != null) '${l['company']}',
            if (l['phone'] != null) '${l['phone']}',
          ].join(' · ')),
          trailing: Chip(label: Text('${l['stage'] ?? ''}')),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
