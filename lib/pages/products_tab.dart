import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import 'common.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _add() async {
    final r = await askFields(context, 'New product', ['Name', 'URL']);
    if (r == null || r['Name']!.isEmpty) return;
    try {
      await Api.post('/products', {'name': r['Name'], 'url': r['URL'] ?? '', 'status': 'building'});
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
        load: () async => items(await Api.get('/products')),
        empty: 'No products yet.',
        row: (c, p, reload) => ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text('${p['name']}'),
          subtitle: Text('${p['status']} ${p['url'] ?? ''}'),
          trailing: (p['url'] ?? '').toString().isEmpty ? null : const Icon(Icons.open_in_new),
          onTap: () {
            var u = '${p['url'] ?? ''}';
            if (u.isEmpty) return;
            if (!u.startsWith('http')) u = 'https://$u';
            launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
    );
  }
}
