import 'package:flutter/material.dart';
import '../models/property.dart';

/// Compact editor shared by a closed area and an open distance path.
class LayerEditorPanel extends StatelessWidget {
  final PropertyLayer layer;
  final String measurement;
  final List<String> errors;
  final VoidCallback onUndo, onClear, onDone, onDelete;
  final ValueChanged<BoundaryPoint> onEditPoint;
  final ValueChanged<int> onInsertPoint;
  const LayerEditorPanel({
    super.key,
    required this.layer,
    required this.measurement,
    required this.errors,
    required this.onUndo,
    required this.onClear,
    required this.onDone,
    required this.onDelete,
    required this.onEditPoint,
    required this.onInsertPoint,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                layer.kind == LayerKind.area
                    ? Icons.crop_square
                    : Icons.straighten,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  layer.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Delete this area or measurement',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(measurement, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            layer.kind == LayerKind.area
                ? 'Tap the map to add corners. Drag a corner to adjust.'
                : 'Tap the map to extend the path. Drag a point to adjust.',
          ),
          if (errors.isNotEmpty)
            Text(
              errors.join('\n'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (layer.points.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${layer.points.length} coordinates'),
              children: [
                SizedBox(
                  height: 120,
                  child: ListView(
                    children: List.generate(layer.points.length, (i) {
                      final point = layer.points[i];
                      final canInsert =
                          layer.points.length >= 2 &&
                          (layer.kind == LayerKind.area ||
                              i < layer.points.length - 1);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${point.label}: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                        ),
                        onTap: () => onEditPoint(point),
                        trailing: canInsert
                            ? IconButton(
                                tooltip: 'Insert after ${point.label}',
                                icon: const Icon(
                                  Icons.add_location_alt_outlined,
                                ),
                                onPressed: () => onInsertPoint(i),
                              )
                            : null,
                      );
                    }),
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: layer.points.isEmpty ? null : onUndo,
                child: const Text('Undo'),
              ),
              TextButton(
                onPressed: layer.points.isEmpty ? null : onClear,
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: errors.isEmpty ? onDone : null,
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Included when you save this property. Planning estimate.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}
