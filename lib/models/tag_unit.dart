import 'dart:math' as math;

/// Unit conversion for map tags only; measured geometry stays in SI units.
enum TagUnit {
  acres('acres', 4046.8564224, 3),
  squareFeet('sq ft', .09290304, 0),
  squareYards('sq yd', .83612736, 1),
  squareMiles('sq mi', 2589988.110336, 3),
  hectares('ha', 10000, 3),
  squareMeters('m²', 1, 1),
  squareKilometers('km²', 1000000, 3),
  feet('ft', .3048, 1),
  yards('yd', .9144, 1),
  miles('mi', 1609.344, 3),
  meters('m', 1, 1),
  centimeters('cm', .01, 1),
  kilometers('km', 1000, 3);

  final String symbol;
  final double siFactor;
  final int decimals;
  const TagUnit(this.symbol, this.siFactor, this.decimals);

  String format(double siValue) {
    final value = siValue / siFactor;
    var precision = decimals;
    // Keep small parcels and short paths meaningful even in large units.
    while (value != 0 &&
        value.abs() < 1 &&
        value.abs() * math.pow(10, precision) < 100 &&
        precision < 8) {
      precision++;
    }
    return '${value.toStringAsFixed(precision)} $symbol';
  }

  static TagUnit? fromName(String? name) =>
      values.where((u) => u.name == name).firstOrNull;
  static List<TagUnit> options({required bool area, required bool metric}) =>
      area
      ? (metric
            ? const [hectares, squareMeters, squareKilometers]
            : const [acres, squareFeet, squareYards, squareMiles])
      : (metric
            ? const [meters, centimeters, kilometers]
            : const [feet, yards, miles]);
}
