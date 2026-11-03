import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/services/assistant/property_tools.dart';
import 'support/assistant_fixtures.dart';

void main() {
  test(
    'tools use an immutable snapshot and return independent layer measurements',
    () {
      final property = exampleProperty(),
          tools = PropertyTools(exampleProperty());
      property.points.clear();
      final summary = tools.execute('get_property_summary', {});
      expect(summary['status'], 'ok');
      expect(summary['layers'], hasLength(2));
      expect((summary['boundary'] as Map)['area_acres'], greaterThan(0));
      expect(jsonEncode(summary), isNot(contains('latitude')));
      final segments = tools.execute('get_boundary_segments', {});
      expect(segments['segments'], hasLength(4));
      expect(segments['segments'][0]['latitude'], 30);
      final area = tools.execute('get_selected_area', {'layer_id': 'garden'});
      expect(area['area_sq_m'], summary['boundary']['area_sq_m']);
      final path = tools.execute('get_measured_path_length', {
        'layer_id': 'driveway',
      });
      expect(path['closed'], false);
      expect(path['length_m'], lessThan(summary['boundary']['perimeter_m']));
      expect(
        tools.execute('get_selected_area', {'layer_id': 'driveway'})['status'],
        'error',
      );
      expect(
        tools.execute('get_measured_path_length', {
          'layer_id': 'missing',
        })['status'],
        'error',
      );
      final original = exampleProperty();
      final snapshot = PropertyTools(original);
      original.points.clear();
      expect(snapshot.execute('get_property_area', {})['status'], 'ok');
      expect(
        PropertyTools(original).execute('get_property_area', {})['status'],
        'error',
      );
    },
  );
  test(
    'gravel volume and weight use exact unit conversions and supplied dimensions',
    () {
      final tools = PropertyTools(exampleProperty());
      final imperial = tools.execute('calculate_gravel_volume', {
        'path_id': null,
        'length': 100,
        'width': 12,
        'depth': 4,
        'unit_system': 'imperial',
        'density_short_tons_per_cubic_yard': 1.4,
      });
      expect(imperial['surface_sq_ft'], closeTo(1200, 1e-8));
      expect(imperial['volume_cubic_yards'], closeTo(400 / 27, 1e-8));
      expect(imperial['weight_us_short_tons'], closeTo(400 / 27 * 1.4, 1e-8));
      final metric = tools.execute('calculate_gravel_tonnage', {
        'path_id': null,
        'length': 30.48,
        'width': 3.6576,
        'depth': 10.16,
        'unit_system': 'metric',
        'density_short_tons_per_cubic_yard': null,
      });
      expect(
        metric['volume_cubic_yards'],
        closeTo(imperial['volume_cubic_yards'], 1e-8),
      );
      expect(metric['assumptions'], contains('planning assumption'));
      final saved = tools.execute('calculate_gravel_volume', {
        'path_id': 'driveway',
        'length': null,
        'width': 12,
        'depth': 4,
        'unit_system': 'imperial',
        'density_short_tons_per_cubic_yard': 1.6,
      });
      expect(
        saved['length_m'],
        tools.execute('get_measured_path_length', {
          'layer_id': 'driveway',
        })['length_m'],
      );
    },
  );
  test(
    'fill volume uses saved area and fence materials distinguish open and closed lines',
    () {
      final tools = PropertyTools(exampleProperty());
      final fill = tools.execute('calculate_material_volume', {
        'layer_id': 'garden',
        'depth': 10,
        'unit_system': 'metric',
      });
      final area = tools.execute('get_selected_area', {'layer_id': 'garden'});
      expect(
        fill['volume_cubic_m'],
        closeTo((area['area_sq_m'] as num) * .1, 1e-8),
      );
      final args = {
        'source': 'manual',
        'layer_id': null,
        'length': 100,
        'spacing': 8,
        'unit_system': 'imperial',
        'closed': false,
      };
      final open = tools.execute('calculate_fence_materials', args);
      final closed = tools.execute('calculate_fence_materials', {
        ...args,
        'closed': true,
      });
      expect(open['spans'], 13);
      expect(open['posts'], 14);
      expect(closed['posts'], 13);
      expect(
        tools.execute('calculate_fence_materials', {
          ...args,
          'source': 'boundary',
        })['length_m'],
        area['perimeter_m'],
      );
    },
  );
  test(
    'cost breakdown computes all line items, tax and contingency from explicit rates',
    () {
      final tools = PropertyTools(exampleProperty());
      final result = tools.execute('calculate_project_cost', {
        'items': [
          {
            'description': 'Gravel',
            'quantity': 10,
            'unit': 'short ton',
            'unit_price': 50,
          },
        ],
        'labor_cost': 200,
        'tax_percent': 10,
        'contingency_percent': 5,
        'currency': 'USD',
      });
      expect(result['materials_subtotal'], 500);
      expect(result['tax'], 70);
      expect(result['contingency'], 38.5);
      expect(result['total'], 808.5);
      expect(result['assumptions'], contains('not verified'));
    },
  );
  test(
    'invalid and overflowing inputs return errors rather than trusted quantities',
    () {
      final tools = PropertyTools(exampleProperty());
      final args = {
        'path_id': null,
        'length': 100,
        'width': 12,
        'depth': 4,
        'unit_system': 'imperial',
        'density_short_tons_per_cubic_yard': null,
      };
      for (final change in [
        {'width': 0},
        {'depth': -1},
        {'length': double.nan},
        {'length': 1e300, 'width': 1e300},
        {'path_id': 'driveway'},
        {'unit_system': 'yards'},
      ]) {
        expect(
          tools.execute('calculate_gravel_volume', {
            ...args,
            ...change,
          })['status'],
          'error',
        );
      }
      expect(tools.execute('arbitrary_write_tool', {})['status'], 'error');
      final invalid = exampleProperty()..points.removeRange(1, 4);
      expect(
        PropertyTools(invalid).execute('get_property_perimeter', {})['status'],
        'error',
      );
    },
  );
}
