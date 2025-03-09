import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kintai_app/models/location_geofence.dart';
import 'package:kintai_app/providers/location_provider.dart';

class LocationEditScreen extends ConsumerStatefulWidget {
  final String companyId;
  final LocationGeofence? location;

  const LocationEditScreen(
      {super.key, required this.companyId, this.location});

  @override
  ConsumerState<LocationEditScreen> createState() =>
      _LocationEditScreenState();
}

class _LocationEditScreenState extends ConsumerState<LocationEditScreen> {
  final _nameController = TextEditingController();
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  double _radius = 200;
  bool _isActive = true;
  bool _loading = false;

  bool get _isEditing => widget.location != null;

  static const _defaultLocation = LatLng(35.6812, 139.7671); // 東京駅

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final loc = widget.location!;
      _nameController.text = loc.name;
      _selectedLocation = LatLng(loc.lat, loc.lng);
      _radius = loc.radius;
      _isActive = loc.isActive;
    }
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    if (_selectedLocation != null) return;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10));
      if (mounted && _selectedLocation == null) {
        setState(() {
          _selectedLocation =
              LatLng(position.latitude, position.longitude);
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_selectedLocation!),
        );
      }
    } catch (e) {
      debugPrint('[LocationEdit] Error getting location: $e');
    }
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty || _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名前を入力し、地図で場所をタップしてください')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final loc = LocationGeofence(
        id: widget.location?.id ?? '',
        name: _nameController.text.trim(),
        lat: _selectedLocation!.latitude,
        lng: _selectedLocation!.longitude,
        radius: _radius,
        isActive: _isActive,
      );
      final service = ref.read(locationServiceProvider);
      if (_isEditing) {
        await service.updateLocation(widget.companyId, loc.id, loc);
      } else {
        await service.addLocation(widget.companyId, loc);
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拠点を削除'),
        content: const Text('この拠点を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(locationServiceProvider)
        .deleteLocation(widget.companyId, widget.location!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '拠点を編集' : '拠点を追加'),
        actions: [
          if (_isEditing)
            IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 拠点名
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '拠点名',
                hintText: '例: 本社オフィス',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // 半径スライダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('半径', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_radius.toInt()}m',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _radius,
              min: 30,
              max: 1000,
              divisions: 97,
              label: '${_radius.toInt()}m',
              onChanged: (value) => setState(() => _radius = value),
            ),
          ),

          // 有効/無効
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SwitchListTile(
              title: const Text('有効'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ),

          // 地図
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedLocation ?? _defaultLocation,
                    zoom: 16,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_selectedLocation != null) {
                      controller.animateCamera(
                        CameraUpdate.newLatLng(_selectedLocation!),
                      );
                    }
                  },
                  onTap: (latLng) {
                    setState(() => _selectedLocation = latLng);
                  },
                  circles: _selectedLocation != null
                      ? {
                          Circle(
                            circleId: const CircleId('geofence'),
                            center: _selectedLocation!,
                            radius: _radius,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                            strokeColor:
                                Theme.of(context).colorScheme.primary,
                            strokeWidth: 2,
                          ),
                        }
                      : {},
                  markers: _selectedLocation != null
                      ? {
                          Marker(
                            markerId: const MarkerId('selected'),
                            position: _selectedLocation!,
                          ),
                        }
                      : {},
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                if (_selectedLocation == null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('地図をタップして拠点の場所を設定'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
