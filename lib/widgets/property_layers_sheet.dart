import 'package:flutter/material.dart';
import '../controllers/property_controller.dart';
import '../models/property.dart';

class PropertyLayersSheet extends StatelessWidget {
  final PropertyController controller;
  final ValueChanged<LayerKind> onCreate;
  final ValueChanged<PropertyLayer> onEdit, onRename, onDelete;
  final String Function(PropertyLayer) measurement;
  const PropertyLayersSheet({
    super.key,
    required this.controller,
    required this.onCreate,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.measurement,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Areas & measurements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Saved with this property. Each shape is measured independently.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => onCreate(LayerKind.area),
                      icon: const Icon(Icons.crop_square),
                      label: const Text('Add area'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => onCreate(LayerKind.distance),
                      icon: const Icon(Icons.straighten),
                      label: const Text('Add measurement'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (controller.property!.layers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No areas or measurements yet. Add one, then tap its points on the map.',
              ),
            ),
          ...controller.property!.layers.map((layer) {
            final errors = controller.layerErrors[layer.id] ?? [];
            return ListTile(
              leading: Icon(
                layer.kind == LayerKind.area
                    ? Icons.crop_square
                    : Icons.straighten,
                color: layer.kind == LayerKind.area
                    ? Colors.orange
                    : Colors.lightBlue,
              ),
              title: Text(layer.name),
              subtitle: Text(
                '${layer.visible ? '' : 'Hidden on map\n'}${errors.isEmpty ? measurement(layer) : errors.join('\n')}',
              ),
              onTap: () => onEdit(layer),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip:
                        '${layer.visible ? 'Hide' : 'Show'} ${layer.name} on map',
                    isSelected: layer.visible,
                    icon: const Icon(Icons.visibility_off_outlined),
                    selectedIcon: const Icon(Icons.visibility_outlined),
                    onPressed: () => controller.toggleLayerVisibility(layer.id),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Manage ${layer.name}',
                    onSelected: (value) =>
                        value == 'rename' ? onRename(layer) : onDelete(layer),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}
