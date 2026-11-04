import 'package:flutter_test/flutter_test.dart';
import 'package:lando/models/property.dart';
import 'package:lando/models/tag_unit.dart';

void main() {
  test('area cycles wrap independently for imperial and metric', () {
    final area = PropertyLayer(
      id: 'area',
      kind: LayerKind.area,
      name: 'Garden',
    );
    for (final unit in [
      TagUnit.acres,
      TagUnit.squareFeet,
      TagUnit.squareYards,
      TagUnit.squareMiles,
    ]) {
      expect(area.tagUnit(metric: false), unit);
      area.cycleTagUnit(metric: false);
    }
    expect(area.tagUnit(metric: false), TagUnit.acres);
    area.cycleTagUnit(metric: false);
    for (final unit in [
      TagUnit.hectares,
      TagUnit.squareMeters,
      TagUnit.squareKilometers,
    ]) {
      expect(area.tagUnit(metric: true), unit);
      area.cycleTagUnit(metric: true);
    }
    expect(area.tagUnit(metric: true), TagUnit.hectares);
    expect(area.tagUnit(metric: false), TagUnit.squareFeet);
    final restored = PropertyLayer.fromJson(area.toJson());
    expect(restored.tagUnit(metric: false), TagUnit.squareFeet);
    expect(restored.tagUnit(metric: true), TagUnit.hectares);
  });
  test(
    'distance cycles stay in the selected system and defaults support old files',
    () {
      final line = PropertyLayer(
        id: 'line',
        kind: LayerKind.distance,
        name: 'Fence',
      );
      for (final unit in [
        TagUnit.feet,
        TagUnit.yards,
        TagUnit.miles,
        TagUnit.feet,
      ]) {
        expect(line.tagUnit(metric: false), unit);
        line.cycleTagUnit(metric: false);
      }
      for (final unit in [
        TagUnit.meters,
        TagUnit.centimeters,
        TagUnit.kilometers,
        TagUnit.meters,
      ]) {
        expect(line.tagUnit(metric: true), unit);
        line.cycleTagUnit(metric: true);
      }
      final legacy = line.toJson()
        ..remove('imperialTagUnit')
        ..remove('metricTagUnit');
      expect(
        PropertyLayer.fromJson(legacy).tagUnit(metric: false),
        TagUnit.feet,
      );
      expect(
        PropertyLayer.fromJson(legacy).tagUnit(metric: true),
        TagUnit.meters,
      );
      line.imperialTagUnit = TagUnit.acres;
      expect(line.tagUnit(metric: false), TagUnit.feet);
    },
  );
  test(
    'conversions use standard exact SI factors and small values remain legible',
    () {
      expect(TagUnit.squareFeet.format(4046.8564224), '43560 sq ft');
      expect(TagUnit.squareYards.format(4046.8564224), '4840.0 sq yd');
      expect(TagUnit.acres.format(2589988.110336), '640.000 acres');
      expect(TagUnit.squareMiles.format(2589988.110336), '1.000 sq mi');
      expect(TagUnit.yards.format(1609.344), '1760.0 yd');
      expect(TagUnit.miles.format(1609.344), '1.000 mi');
      expect(TagUnit.feet.format(1609.344), '5280.0 ft');
      expect(TagUnit.hectares.format(10000), '1.000 ha');
      expect(TagUnit.squareMeters.format(10000), '10000.0 m²');
      expect(TagUnit.squareKilometers.format(1000000), '1.000 km²');
      expect(TagUnit.centimeters.format(1), '100.0 cm');
      expect(TagUnit.kilometers.format(1000), '1.000 km');
      expect(TagUnit.squareMiles.format(4046.8564224), '0.00156 sq mi');
      expect(TagUnit.miles.format(.3048), '0.000189 mi');
    },
  );
}
