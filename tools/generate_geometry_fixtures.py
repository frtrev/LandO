"""Optional fixture regeneration: pip install geographiclib==2.1.
Run from the repository root. GeographicLib is a test oracle, not an app dependency.
"""
import json
from geographiclib.geodesic import Geodesic

CASES = {
    'equator': [(0, 0), (0, .001), (.001, .001), (.001, 0)],
    'texas': [(30, -98), (30, -97.999), (30.001, -97.999), (30.001, -98)],
    'concave': [(30, -98), (30, -97.998), (30.001, -97.999), (30.002, -97.998), (30.002, -98)],
    'dateline': [(10, 179.999), (10, -179.999), (10.001, -179.999), (10.001, 179.999)],
    'highlatitude': [(80, 15), (80, 15.1), (80.1, 15.1), (80.1, 15)],
    'large': [(45, -100), (45, -99), (45.5, -99), (45.5, -100)],
}
fixtures = []
for name, coords in CASES.items():
    polygon = Geodesic.WGS84.Polygon()
    for lat, lon in coords:
        polygon.AddPoint(lat, lon)
    _, perimeter, area = polygon.Compute()
    fixtures.append(dict(name=name, coords=coords, area=abs(area), perimeter=perimeter))
with open('test/geographiclib_fixtures.json', 'w') as output:
    json.dump(fixtures, output, indent=2)
    output.write('\n')
