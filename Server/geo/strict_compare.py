"""Strict parity check: saved public-server answers vs a local server, for points the public
server places inside the given country. Compares the OSM object and the exact GeoJSON.

usage: python3 strict_compare.py <points.json> <public-answers-dir> <country-code> <local-base-url>
"""
import json
import sys
import urllib.request

PARAMS = "format=jsonv2&zoom=10&polygon_geojson=1&polygon_threshold=0.0005"


def local(base, p):
    url = f"{base}/reverse?{PARAMS}&lat={p['lat']:.5f}&lon={p['lon']:.5f}"
    req = urllib.request.Request(url, headers={"User-Agent": "TripAtlas-parity-check/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main():
    points = json.load(open(sys.argv[1]))
    folder, country, base = sys.argv[2], sys.argv[3], sys.argv[4]
    inside = same = 0
    diffs = []
    for p in points:
        pub = json.load(open(f"{folder}/{p['id']}.json"))
        if (pub.get("address") or {}).get("country_code") != country:
            continue
        inside += 1
        loc = local(base, p)
        a = (pub.get("osm_type"), pub.get("osm_id"), json.dumps(pub.get("geojson"), sort_keys=True))
        b = (loc.get("osm_type"), loc.get("osm_id"), json.dumps(loc.get("geojson"), sort_keys=True))
        if a == b:
            same += 1
        else:
            diffs.append((p["id"], p.get("label"), a[:2], b[:2], a[2] == b[2]))
    print(f"{country}: {same}/{inside} points with the same object and byte-identical GeoJSON")
    for d in diffs[:15]:
        print("  DIFF", d)
    return 0 if same == inside and inside > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
