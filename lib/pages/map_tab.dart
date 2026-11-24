import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import 'common.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});
  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  bool _crm = false;
  bool _loading = true;
  String _err = '';
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final r = await Api.get(_crm ? '/leads' : '/pins');
      _data = items(r).where((e) => e['latitude'] != null && e['longitude'] != null).toList();
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  LatLng? _pt(Map<String, dynamic> e) {
    final la = double.tryParse('${e['latitude']}');
    final lo = double.tryParse('${e['longitude']}');
    return (la == null || lo == null) ? null : LatLng(la, lo);
  }

  Future<void> _addPin(LatLng p) async {
    if (_crm) return;
    final r = await askFields(context, 'Pin this place', ['Title', 'Note']);
    if (r == null || r['Title']!.isEmpty) return;
    try {
      await Api.post('/pins', {
        'title': r['Title'],
        'note': r['Note'] ?? '',
        'address': '',
        'latitude': p.latitude,
        'longitude': p.longitude,
      });
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  void _show(Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e[_crm ? 'name' : 'title']}', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(_crm ? '${e['company'] ?? ''} ${e['stage'] ?? ''}' : '${e['note'] ?? ''}'),
            if ('${e['address'] ?? ''}'.isNotEmpty) Text('${e['address']}'),
            if (!_crm)
              TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(c);
                    try {
                      await Api.del('/pins/${e['id']}');
                    } catch (er) {
                      if (mounted) toast(context, '$er');
                    }
                    _load();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete pin')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final e in _data) {
      final p = _pt(e);
      if (p == null) continue;
      markers.add(Marker(
        point: p,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _show(e),
          child: Icon(Icons.location_on, size: 40, color: _crm ? Colors.orange : Colors.red),
        ),
      ));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Places')),
            ButtonSegment(value: true, label: Text('CRM leads')),
          ],
          selected: {_crm},
          onSelectionChanged: (s) {
            _crm = s.first;
            _load();
          },
        ),
      ),
      if (_err.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_err)),
      Expanded(
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: markers.isNotEmpty ? markers.first.point : const LatLng(23.0225, 72.5714),
              initialZoom: 11,
              onLongPress: (tp, p) => _addPin(p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'pro.yashchauhan.glob_app',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          if (_loading) const Positioned(top: 8, right: 8, child: CircularProgressIndicator()),
          if (!_crm)
            const Positioned(
                bottom: 8,
                left: 8,
                child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(8), child: Text('Long-press the map to pin a place')))),
        ]),
      ),
    ]);
  }
}
