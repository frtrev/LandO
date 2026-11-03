import '../../models/property.dart';
import '../geometry_service.dart';

/// Read-only calculation tools: the assistant cannot write property geometry.
class PropertyTools {
  final Property property;
  final GeometryService geometry;
  PropertyTools(Property source, {GeometryService? geometry})
    : property = Property.fromJson(source.toJson()),
      geometry = geometry ?? GeometryService();
  static Map<String, dynamic> _string(
    String description, {
    bool nullable = false,
  }) => {
    'type': nullable ? ['string', 'null'] : 'string',
    'description': description,
  };
  static Map<String, dynamic> _number(
    String description, {
    bool nullable = false,
  }) => {
    'type': nullable ? ['number', 'null'] : 'number',
    'description': description,
  };
  static Map<String, dynamic> _enum(List<String> values) => {
    'type': 'string',
    'enum': values,
  };
  static Map<String, dynamic> _object(Map<String, dynamic> properties) => {
    'type': 'object',
    'properties': properties,
    'required': properties.keys.toList(),
    'additionalProperties': false,
  };
  static Map<String, dynamic> _tool(
    String name,
    String description,
    Map<String, dynamic> parameters,
  ) => {
    'type': 'function',
    'name': name,
    'description': description,
    'parameters': _object(parameters),
    'strict': true,
  };
  static Map<String, dynamic> get _gravelParameters => {
    'path_id': _string(
      'Saved distance path ID, or null for a manually supplied length.',
      nullable: true,
    ),
    'length': _number(
      'Manual length; null when path_id is supplied.',
      nullable: true,
    ),
    'width': _number(
      'Width: feet for imperial, meters for metric. Must be supplied by user.',
    ),
    'depth': _number(
      'Depth: inches for imperial, centimeters for metric. Must be supplied by user.',
    ),
    'unit_system': _enum(['imperial', 'metric']),
    'density_short_tons_per_cubic_yard': _number(
      'User density, or null for explicitly labeled 1.4 short tons/yd³ planning assumption.',
      nullable: true,
    ),
  };
  static List<Map<String, dynamic>> get definitions => [
    _tool(
      'get_property_summary',
      'Read the current property and independent area/path summaries. Always consult fresh results, not historical chat values.',
      {},
    ),
    _tool(
      'get_property_area',
      'Get validated property acreage, square feet, square meters and hectares.',
      {},
    ),
    _tool(
      'get_property_perimeter',
      'Get validated property perimeter in feet and meters.',
      {},
    ),
    _tool(
      'get_boundary_segments',
      'Get ordered property segment lengths and exact boundary coordinates.',
      {},
    ),
    _tool(
      'get_selected_area',
      'Get a named area by its exact layer ID from the summary.',
      {'layer_id': _string('Area layer ID.')},
    ),
    _tool(
      'get_measured_path_length',
      'Get an independent open path by its exact layer ID.',
      {'layer_id': _string('Distance layer ID.')},
    ),
    _tool(
      'calculate_gravel_volume',
      'Compute rectangular path surface area and gravel volume. Ask for missing width/depth first.',
      _gravelParameters,
    ),
    _tool(
      'calculate_gravel_tonnage',
      'Compute gravel volume and US short tons using an explicit density assumption.',
      _gravelParameters,
    ),
    _tool(
      'calculate_material_volume',
      'Compute topsoil or other fill volume for a saved area and a supplied depth.',
      {
        'layer_id': _string('Saved area ID.'),
        'depth': _number('Depth in inches (imperial) or centimeters (metric).'),
        'unit_system': _enum(['imperial', 'metric']),
      },
    ),
    _tool(
      'calculate_fence_materials',
      'Estimate posts and spans from a boundary, saved area/path or supplied length, without gates. Ask for spacing if missing.',
      {
        'source': _enum(['boundary', 'area', 'path', 'manual']),
        'layer_id': _string(
          'Area/path ID, or null for boundary/manual.',
          nullable: true,
        ),
        'length': _number(
          'Manual length in feet or meters; null for a saved geometry.',
          nullable: true,
        ),
        'spacing': _number(
          'Maximum post spacing in feet (imperial) or meters (metric).',
        ),
        'unit_system': _enum(['imperial', 'metric']),
        'closed': {
          'type': 'boolean',
          'description':
              'Manual line is closed; ignored when geometry determines closure.',
        },
      },
    ),
    _tool(
      'calculate_project_cost',
      'Compute a cost breakdown from supplied quantities, unit prices and explicit rates. These are estimates, not verified current prices.',
      {
        'items': {
          'type': 'array',
          'items': _object({
            'description': _string('Material or service.'),
            'quantity': _number(
              'Nonnegative quantity from user or a calculation tool.',
            ),
            'unit': _string('Quantity unit.'),
            'unit_price': _number('Nonnegative supplied price per unit.'),
          }),
        },
        'labor_cost': _number(
          'Total user-supplied labor cost; zero only if excluded explicitly.',
        ),
        'tax_percent': _number(
          'Tax percentage applied to materials and labor.',
        ),
        'contingency_percent': _number(
          'Contingency percentage applied to taxed subtotal.',
        ),
        'currency': _string('User specified currency code, e.g. USD.'),
      },
    ),
  ];
  Map<String, dynamic> _area(List<BoundaryPoint> points) {
    final r = geometry.calculate(points);
    if (!r.valid) {
      throw FormatException(r.errors.join(' '));
    }
    return {
      'area_acres': r.acres,
      'area_sq_ft': r.squareFeet,
      'area_sq_m': r.squareMeters,
      'area_hectares': r.hectares,
      'perimeter_ft': r.perimeterMeters! / .3048,
      'perimeter_m': r.perimeterMeters,
    };
  }

  PropertyLayer _layer(Object? id, LayerKind kind) {
    final found = property.layers
        .where((l) => l.id == id && l.kind == kind)
        .firstOrNull;
    if (found == null) {
      throw const FormatException(
        'The requested layer does not exist or has a different type. Ask the user which layer they mean.',
      );
    }
    return found;
  }

  double _path(PropertyLayer layer) {
    if (layer.points.length < 2) {
      throw const FormatException('The path needs at least two valid points.');
    }
    for (var i = 1; i < layer.points.length; i++) {
      if (geometry.distance(layer.points[i - 1], layer.points[i]) < .001) {
        throw const FormatException(
          'The path contains duplicate consecutive points.',
        );
      }
    }
    return geometry.pathLength(layer.points);
  }

  double _num(
    Map<String, dynamic> args,
    String key, {
    bool zero = false,
    double? maximum,
  }) {
    final n = args[key];
    if (n is! num ||
        !n.toDouble().isFinite ||
        (zero ? n < 0 : n <= 0) ||
        (maximum != null && n > maximum)) {
      throw FormatException(
        'Supply a valid ${zero ? 'nonnegative' : 'positive'} $key${maximum == null ? '' : ' no greater than $maximum'}.',
      );
    }
    return n.toDouble();
  }

  bool _metric(Map<String, dynamic> args) {
    if (args['unit_system'] != 'metric' && args['unit_system'] != 'imperial') {
      throw const FormatException('Specify imperial or metric units.');
    }
    return args['unit_system'] == 'metric';
  }

  Map<String, dynamic> execute(String name, Map<String, dynamic> args) {
    try {
      final result = _execute(name, args);
      _ensureFinite(result);
      return {
        'status': 'ok',
        'measurement_method':
            'Map-derived planning estimate; not a legal survey.',
        ...result,
      };
    } on Object catch (e) {
      return {
        'status': 'error',
        'error': e is FormatException
            ? e.message
            : 'Could not calculate this request. Check the supplied inputs.',
      };
    }
  }

  void _ensureFinite(Object? value) {
    if (value is num && !value.isFinite) {
      throw const FormatException(
        'Inputs exceed the supported calculation range.',
      );
    }
    if (value is Map) {
      for (final child in value.values) {
        _ensureFinite(child);
      }
    }
    if (value is List) {
      for (final child in value) {
        _ensureFinite(child);
      }
    }
  }

  Map<String, dynamic> _execute(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'get_property_summary':
        final boundary = execute('get_property_area', {});
        return {
          'property_name': property.name,
          'description': property.description,
          'preferred_units': property.metric ? 'metric' : 'imperial',
          'boundary': boundary,
          'layers': property.layers
              .map(
                (layer) => {
                  'id': layer.id,
                  'name': layer.name,
                  'kind': layer.kind.name,
                  'measurements': execute(
                    layer.kind == LayerKind.area
                        ? 'get_selected_area'
                        : 'get_measured_path_length',
                    {'layer_id': layer.id},
                  ),
                },
              )
              .toList(),
          'assumptions':
              'Areas are independent and may overlap or extend outside the property. Do not sum or subtract them as a union.',
        };
      case 'get_property_area':
        return _area(property.points);
      case 'get_property_perimeter':
        final r = _area(property.points);
        return {
          'perimeter_ft': r['perimeter_ft'],
          'perimeter_m': r['perimeter_m'],
        };
      case 'get_boundary_segments':
        final r = geometry.calculate(property.points);
        if (!r.valid) {
          throw FormatException(r.errors.join(' '));
        }
        return {
          'segments': List.generate(property.points.length, (i) {
            final p = property.points[i],
                q = property.points[(i + 1) % property.points.length];
            return {
              'from': p.label,
              'to': q.label,
              'length_m': r.segments[i],
              'length_ft': r.segments[i] / .3048,
              'latitude': p.latitude,
              'longitude': p.longitude,
            };
          }),
        };
      case 'get_selected_area':
        final layer = _layer(args['layer_id'], LayerKind.area);
        return {'name': layer.name, ..._area(layer.points)};
      case 'get_measured_path_length':
        final layer = _layer(args['layer_id'], LayerKind.distance),
            length = _path(layer);
        return {
          'name': layer.name,
          'length_m': length,
          'length_ft': length / .3048,
          'closed': false,
        };
      case 'calculate_gravel_volume':
      case 'calculate_gravel_tonnage':
        final metric = _metric(args);
        if (args['path_id'] != null && args['length'] != null) {
          throw const FormatException(
            'Use either a saved path or a manual length, not both.',
          );
        }
        final length = args['path_id'] == null
            ? _num(args, 'length') * (metric ? 1 : .3048)
            : _path(_layer(args['path_id'], LayerKind.distance));
        final width = _num(args, 'width') * (metric ? 1 : .3048),
            depth = _num(args, 'depth') * (metric ? .01 : .0254);
        final volume = length * width * depth, yards = volume / .764554857984;
        final density = args['density_short_tons_per_cubic_yard'] == null
            ? 1.4
            : _num(args, 'density_short_tons_per_cubic_yard');
        return {
          'length_m': length,
          'length_ft': length / .3048,
          'width_m': width,
          'depth_m': depth,
          'surface_sq_m': length * width,
          'surface_sq_ft': length * width / .09290304,
          'volume_cubic_m': volume,
          'volume_cubic_yards': yards,
          'density_short_tons_per_cubic_yard': density,
          'weight_us_short_tons': yards * density,
          'assumptions':
              'Rectangular constant width/depth, no compaction or waste allowance. ${args['density_short_tons_per_cubic_yard'] == null ? 'Density of 1.4 US short tons/yd³ is a planning assumption, not a measured material specification.' : 'Uses supplied density.'}',
        };
      case 'calculate_material_volume':
        final layer = _layer(args['layer_id'], LayerKind.area);
        final area = _area(layer.points)['area_sq_m'] as double,
            depth = _num(args, 'depth') * (_metric(args) ? .01 : .0254),
            volume = area * depth;
        return {
          'name': layer.name,
          'area_sq_m': area,
          'depth_m': depth,
          'volume_cubic_m': volume,
          'volume_cubic_yards': volume / .764554857984,
          'assumptions': 'Uniform depth, no compaction or waste allowance.',
        };
      case 'calculate_fence_materials':
        final spacing = _num(args, 'spacing') * (_metric(args) ? 1 : .3048);
        double length;
        bool closed;
        switch (args['source']) {
          case 'boundary':
            length = _area(property.points)['perimeter_m'] as double;
            closed = true;
          case 'area':
            length =
                _area(
                      _layer(args['layer_id'], LayerKind.area).points,
                    )['perimeter_m']
                    as double;
            closed = true;
          case 'path':
            length = _path(_layer(args['layer_id'], LayerKind.distance));
            closed = false;
          case 'manual':
            length = _num(args, 'length') * (_metric(args) ? 1 : .3048);
            if (args['closed'] is! bool) {
              throw const FormatException(
                'Specify whether the manual fence is closed.',
              );
            }
            closed = args['closed'] as bool;
          default:
            throw const FormatException(
              'Choose boundary, area, path or manual source.',
            );
        }
        final spans = (length / spacing).ceil();
        return {
          'length_m': length,
          'length_ft': length / .3048,
          'maximum_spacing_m': spacing,
          'spans': spans,
          'posts': closed ? spans : spans + 1,
          'closed': closed,
          'assumptions':
              'Length-based estimate with one panel per span, no gates, corners, bracing or terrain allowance. Corners may need extra posts. Verify the layout before purchasing.',
        };
      case 'calculate_project_cost':
        final raw = args['items'];
        if (raw is! List || raw.isEmpty || raw.length > 100) {
          throw const FormatException('Provide between 1 and 100 cost items.');
        }
        var subtotal = 0.0;
        final items = raw.map((value) {
          if (value is! Map) {
            throw const FormatException('Invalid cost item.');
          }
          final item = Map<String, dynamic>.from(value);
          if (item['description'] is! String || item['unit'] is! String) {
            throw const FormatException(
              'Each item needs a description and unit.',
            );
          }
          final total =
              _num(item, 'quantity', zero: true) *
              _num(item, 'unit_price', zero: true);
          subtotal += total;
          return {...item, 'line_total': total};
        }).toList();
        final labor = _num(args, 'labor_cost', zero: true),
            taxRate = _num(args, 'tax_percent', zero: true, maximum: 100),
            contingencyRate = _num(
              args,
              'contingency_percent',
              zero: true,
              maximum: 100,
            );
        final tax = (subtotal + labor) * taxRate / 100,
            contingency = (subtotal + labor + tax) * contingencyRate / 100;
        if (args['currency'] is! String ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(args['currency'] as String)) {
          throw const FormatException(
            'Specify a three-letter uppercase currency code.',
          );
        }
        return {
          'items': items,
          'materials_subtotal': subtotal,
          'labor_cost': labor,
          'tax_percent': taxRate,
          'tax': tax,
          'contingency_percent': contingencyRate,
          'contingency': contingency,
          'total': subtotal + labor + tax + contingency,
          'currency': args['currency'],
          'assumptions':
              'Estimate from supplied quantities and rates. Prices are not verified current market prices. Tax applies to materials plus labor; contingency applies after tax.',
        };
      default:
        throw const FormatException(
          'Unknown tool. Use only the advertised calculation tools.',
        );
    }
  }
}
