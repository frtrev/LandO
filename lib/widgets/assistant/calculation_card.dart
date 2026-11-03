import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

/// The authoritative tool output is shown separately from generated prose.
class CalculationCard extends StatelessWidget {
  final CalculationRecord record;
  const CalculationCard({super.key, required this.record});
  static const labels = {
    'get_property_summary': 'Property summary',
    'get_property_area': 'Property area',
    'get_property_perimeter': 'Boundary length',
    'get_boundary_segments': 'Boundary segments',
    'get_selected_area': 'Saved area',
    'get_measured_path_length': 'Saved measurement',
    'calculate_gravel_volume': 'Gravel volume',
    'calculate_gravel_tonnage': 'Gravel weight',
    'calculate_material_volume': 'Fill volume',
    'calculate_fence_materials': 'Fence materials',
    'calculate_project_cost': 'Project cost estimate',
    'area_acres': 'Area (acres)',
    'area_sq_ft': 'Area (sq ft)',
    'area_sq_m': 'Area (m²)',
    'area_hectares': 'Area (hectares)',
    'perimeter_ft': 'Perimeter (ft)',
    'perimeter_m': 'Perimeter (m)',
    'length_m': 'Length (m)',
    'length_ft': 'Length (ft)',
    'width_m': 'Width (m)',
    'depth_m': 'Depth (m)',
    'surface_sq_m': 'Surface area (m²)',
    'surface_sq_ft': 'Surface area (sq ft)',
    'volume_cubic_m': 'Volume (m³)',
    'volume_cubic_yards': 'Volume (cubic yards)',
    'weight_us_short_tons': 'Weight (US short tons)',
    'density_short_tons_per_cubic_yard':
        'Density (US short tons per cubic yard)',
    'maximum_spacing_m': 'Maximum spacing (m)',
    'closed': 'Closed loop',
    'line_total': 'Line total',
  };
  String title(String key) {
    if (labels.containsKey(key)) {
      return labels[key]!;
    }
    final text = key.replaceAll('_', ' ');
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  String display(Object? value) {
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    if (value is double) {
      if (value != 0 && value.abs() < .001) {
        return value.toStringAsPrecision(4);
      }
      return value.abs() >= 1000000
          ? value.toStringAsPrecision(8)
          : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return value?.toString() ?? 'Unavailable';
  }

  Widget values(Map data, {int depth = 0}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in data.entries)
        if (entry.key != 'measurement_method' &&
            entry.key != 'status' &&
            entry.key != 'id')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: entry.value is Map
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(entry.key as String),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: values(entry.value as Map, depth: depth + 1),
                      ),
                    ],
                  )
                : entry.value is List
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(entry.key as String),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final item in entry.value as List)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: item is Map
                              ? values(item, depth: depth + 1)
                              : Text(display(item)),
                        ),
                    ],
                  )
                : Text(
                    '${title(entry.key as String)}: ${display(entry.value)}',
                  ),
          ),
    ],
  );
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ExpansionTile(
      title: Text(title(record.tool), style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        record.data['status'] == 'error'
            ? 'Calculation unavailable'
            : 'Calculated by LandO · planning estimate',
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: values(record.data),
        ),
      ],
    ),
  );
}
