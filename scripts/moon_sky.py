"""Where the Moon is from San José, and how its disk is turned, with Astronomy Engine.

Prototype of the sky mode's math, checked against NASA JPL Horizons.

Usage:
  pip install astronomy-engine
  python3 -I scripts/moon_sky.py                      # hackathon window, Sat 14 Nov 2026
  python3 -I scripts/moon_sky.py 2026-10-23T20:00     # any local time(s) in San José (UTC-6)
  python3 -I scripts/moon_sky.py --horizons           # also fetch JPL Horizons and compare

For each time it prints the Moon's altitude/azimuth, illumination, libration,
how far its north pole is turned from straight up on screen, and the Sun's
elevation at each Apollo site (lit or in shadow).
"""
import json
import math
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

import astronomy as ae

# San José, Costa Rica (center), elevation ~1170 m.
LAT, LON, ELEV_M = 9.9281, -84.0907, 1170.0
LOCAL = timezone(timedelta(hours=-6))
OBSERVER = ae.Observer(LAT, LON, ELEV_M)

HACKATHON_WINDOW = ["2026-11-14T18:00", "2026-11-14T19:00", "2026-11-14T20:00",
                    "2026-11-14T21:00", "2026-11-14T21:30"]

SITES = json.loads((Path(__file__).resolve().parent.parent / "Data" / "sites.json").read_text(encoding="utf-8"))["sites"]


def to_time(local_iso):
    dt = datetime.fromisoformat(local_iso).replace(tzinfo=LOCAL).astimezone(timezone.utc)
    return ae.Time.Make(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)


def rot3(v, deg):
    """Passive rotation about z (rotates the frame by deg)."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (c * v[0] + s * v[1], -s * v[0] + c * v[1], v[2])


def rot1(v, deg):
    """Passive rotation about x."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return (v[0], c * v[1] + s * v[2], -s * v[1] + c * v[2])


def to_moon_fixed(v, axis):
    """J2000 equatorial vector -> Moon body-fixed frame (IAU model: R3(W) R1(90-dec0) R3(90+ra0))."""
    v = rot3(v, 90 + axis.ra * 15)
    v = rot1(v, 90 - axis.dec)
    return rot3(v, axis.spin)


def unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def moon_state(time):
    of_date = ae.Equator(ae.Body.Moon, time, OBSERVER, ofdate=True, aberration=True)
    hor = ae.Horizon(time, OBSERVER, of_date.ra, of_date.dec, ae.Refraction.Normal)
    j2000 = ae.Equator(ae.Body.Moon, time, OBSERVER, ofdate=False, aberration=True)
    illum = ae.Illumination(ae.Body.Moon, time)
    lib = ae.Libration(time)
    axis = ae.RotationAxis(ae.Body.Moon, time)

    # Position angle of the Moon's north pole, east of celestial north (J2000).
    a, d = math.radians(j2000.ra * 15), math.radians(j2000.dec)
    ap, dp = math.radians(axis.ra * 15), math.radians(axis.dec)
    pole_pa = math.degrees(math.atan2(math.cos(dp) * math.sin(ap - a),
                                      math.sin(dp) * math.cos(d) - math.cos(dp) * math.sin(d) * math.cos(ap - a))) % 360

    # Parallactic angle: how celestial north is tilted from the zenith at this place and time.
    lst_hours = ae.SiderealTime(time) + LON / 15
    h = math.radians((lst_hours - of_date.ra) * 15)
    phi, dec = math.radians(LAT), math.radians(of_date.dec)
    parallactic = math.degrees(math.atan2(math.sin(h), math.tan(phi) * math.cos(dec) - math.sin(dec) * math.cos(h)))

    # Sun and Earth seen from the Moon, in the Moon's own frame.
    moon = ae.GeoVector(ae.Body.Moon, time, True)
    sun = ae.GeoVector(ae.Body.Sun, time, True)
    sun_dir = unit(to_moon_fixed((sun.x - moon.x, sun.y - moon.y, sun.z - moon.z), axis))
    earth_dir = unit(to_moon_fixed((-moon.x, -moon.y, -moon.z), axis))
    sub_earth_lat = math.degrees(math.asin(earth_dir[2]))
    sub_earth_lon = math.degrees(math.atan2(earth_dir[1], earth_dir[0]))

    sites = []
    for s in SITES:
        lat, lon = math.radians(s["coordinates"]["lat"]), math.radians(s["coordinates"]["lon"])
        normal = (math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))
        sun_elev = math.degrees(math.asin(sum(n * c for n, c in zip(normal, sun_dir))))
        sites.append((s["mission"], sun_elev))

    return {
        "alt": hor.altitude, "az": hor.azimuth,
        "illum": illum.phase_fraction * 100, "phase_angle": illum.phase_angle,
        "lib_lat": lib.elat, "lib_lon": lib.elon,
        "sub_earth_lat": sub_earth_lat, "sub_earth_lon": sub_earth_lon,
        "pole_pa": pole_pa, "parallactic": parallactic,
        # Angle of the Moon's north from straight up on screen, counterclockwise.
        "north_from_up": (pole_pa - parallactic + 180) % 360 - 180,
        "sites": sites,
    }


def horizons(local_isos):
    """Azimuth/elevation, illumination, sub-observer point and pole angle from JPL Horizons."""
    utc = [datetime.fromisoformat(t).replace(tzinfo=LOCAL).astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M")
           for t in local_isos]
    params = {
        "format": "text", "COMMAND": "'301'", "OBJ_DATA": "NO", "MAKE_EPHEM": "YES", "EPHEM_TYPE": "OBSERVER",
        "CENTER": "'coord@399'", "COORD_TYPE": "'GEODETIC'",
        "SITE_COORD": f"'{LON},{LAT},{ELEV_M / 1000}'",
        "TLIST": " ".join(f"'{t}'" for t in utc), "TIME_TYPE": "UT",
        "QUANTITIES": "'4,10,14,17'", "ANG_FORMAT": "DEG", "APPARENT": "REFRACTED", "CSV_FORMAT": "YES",
    }
    url = "https://ssd.jpl.nasa.gov/api/horizons.api?" + urllib.parse.urlencode(params)
    text = urllib.request.urlopen(url, timeout=60).read().decode()
    rows = text.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines()
    out = []
    for row in rows:
        f = [c.strip() for c in row.split(",")]
        # date, solar flag, lunar flag, azi, elev, illu%, obs-sub-lon (0-360 E), obs-sub-lat, NP.ang, NP.dist
        out.append({"az": float(f[3]), "alt": float(f[4]), "illum": float(f[5]),
                    "sub_lon": (float(f[6]) + 180) % 360 - 180, "sub_lat": float(f[7]), "pole_pa": float(f[8])})
    return out


def rise_set(local_day):
    start = to_time(local_day + "T12:00")
    rise = ae.SearchRiseSet(ae.Body.Moon, OBSERVER, ae.Direction.Rise, start.AddDays(-1), 2)
    sets = ae.SearchRiseSet(ae.Body.Moon, OBSERVER, ae.Direction.Set, start, 1)
    fmt = lambda t: t.Utc().replace(tzinfo=timezone.utc).astimezone(LOCAL).strftime("%a %d %b %H:%M") if t else "—"
    return fmt(rise), fmt(sets)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    times = args or HACKATHON_WINDOW
    rise, sets = rise_set(times[0][:10])
    print(f"San José {LAT}° N {abs(LON)}° W · Moonrise {rise} · Moonset {sets} (local, UTC-6)\n")

    states = [moon_state(to_time(t)) for t in times]
    print(f"{'local time':17} {'alt°':>6} {'az°':>6} {'lit%':>5} {'lib lat':>8} {'lib lon':>8} {'pole PA':>8} {'parall.':>8} {'N vs up':>8}")
    for t, s in zip(times, states):
        print(f"{t:17} {s['alt']:6.1f} {s['az']:6.1f} {s['illum']:5.1f} {s['lib_lat']:8.2f} {s['lib_lon']:8.2f} "
              f"{s['pole_pa']:8.2f} {s['parallactic']:8.2f} {s['north_from_up']:8.2f}")

    s = states[0]
    print(f"\nSelf-check, sub-Earth point from the IAU frame: lat {s['sub_earth_lat']:.2f}, lon {s['sub_earth_lon']:.2f} "
          f"(libration says {s['lib_lat']:.2f}, {s['lib_lon']:.2f})")
    print(f"\nSun elevation at each site, {times[0]} (negative = in shadow):")
    for mission, elev in s["sites"]:
        print(f"  {mission:10} {elev:6.1f}°  {'lit' if elev > 0 else 'dark'}")

    if "--horizons" in sys.argv:
        ref = horizons(times)
        # Horizons' sub-observer point is seen from San José; Libration() is geocentric,
        # so ~0.5-1° of difference there is the parallax of being on Earth's surface, not an error.
        print("\nAstronomy Engine minus JPL Horizons:")
        print(f"{'local time':17} {'Δalt°':>7} {'Δaz°':>7} {'Δlit%':>6} {'Δlib lat':>9} {'Δlib lon':>9} {'Δpole PA':>9}")
        for t, s, h in zip(times, states, ref):
            d_az = (s["az"] - h["az"] + 180) % 360 - 180
            d_pa = (s["pole_pa"] - h["pole_pa"] + 180) % 360 - 180
            print(f"{t:17} {s['alt'] - h['alt']:7.3f} {d_az:7.3f} {s['illum'] - h['illum']:6.2f} "
                  f"{s['lib_lat'] - h['sub_lat']:9.3f} {s['lib_lon'] - h['sub_lon']:9.3f} {d_pa:9.3f}")


if __name__ == "__main__":
    main()
