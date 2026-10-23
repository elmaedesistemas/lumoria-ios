import CAstronomy
import Foundation
import simd

/// The Moon as seen from one place at one moment: where to look, how lit it is,
/// how its disk is turned, and which landing sites are in daylight.
/// Same math as scripts/moon_sky.py, which is checked against JPL Horizons.
struct SkySnapshot: Sendable {
    var date: Date
    /// Degrees above the horizon, with normal refraction.
    var altitude: Double
    /// Degrees clockwise from true north.
    var azimuth: Double
    var illuminatedFraction: Double
    /// Libration: the sub-Earth point on the Moon, in degrees.
    var librationLat: Double
    var librationLon: Double
    /// Position angle of the Moon's north pole, east of celestial north.
    var polePositionAngle: Double
    /// How celestial north is tilted from the zenith here and now.
    var parallacticAngle: Double
    /// Lunar north on screen, counterclockwise from straight up.
    var northFromUp: Double
    /// The middle of the lit limb on screen, counterclockwise from straight up.
    var brightLimbFromUp: Double
    /// Sun elevation in degrees at each site, keyed by site id; above 0 is daylight.
    var siteSunElevation: [String: Double]
    var moonrise: Date?
    var moonset: Date?

    var isUp: Bool { altitude > 0 }
}

enum SkyModel {
    /// San José, Costa Rica: the event's city, used when the device location is unknown.
    static let sanJose = (latitude: 9.9281, longitude: -84.0907, height: 1170.0)

    static func snapshot(at date: Date, latitude: Double, longitude: Double, height: Double,
                         sites: [LandingSite]) -> SkySnapshot {
        var time = astroTime(date)
        let observer = astro_observer_t(latitude: latitude, longitude: longitude, height: height)

        let ofDate = Astronomy_Equator(BODY_MOON, &time, observer, EQUATOR_OF_DATE, ABERRATION)
        let horizon = Astronomy_Horizon(&time, observer, ofDate.ra, ofDate.dec, REFRACTION_NORMAL)
        let j2000 = Astronomy_Equator(BODY_MOON, &time, observer, EQUATOR_J2000, ABERRATION)
        let illumination = Astronomy_Illumination(BODY_MOON, time)
        let libration = Astronomy_Libration(time)
        let axis = Astronomy_RotationAxis(BODY_MOON, &time)
        let sunEq = Astronomy_Equator(BODY_SUN, &time, observer, EQUATOR_J2000, ABERRATION)

        let poleAngle = positionAngle(ofRA: axis.ra * 15, dec: axis.dec, fromRA: j2000.ra * 15, dec: j2000.dec)
        let brightLimb = positionAngle(ofRA: sunEq.ra * 15, dec: sunEq.dec, fromRA: j2000.ra * 15, dec: j2000.dec)

        let lstHours = Astronomy_SiderealTime(&time) + longitude / 15
        let hourAngle = radians((lstHours - ofDate.ra) * 15)
        let φ = radians(latitude), δ = radians(ofDate.dec)
        let parallactic = degrees(atan2(sin(hourAngle), tan(φ) * cos(δ) - sin(δ) * cos(hourAngle)))

        // The Sun seen from the Moon, in the Moon's own (IAU) frame.
        let moon = Astronomy_GeoVector(BODY_MOON, time, ABERRATION)
        let sun = Astronomy_GeoVector(BODY_SUN, time, ABERRATION)
        let sunDir = toMoonFixed(SIMD3(sun.x - moon.x, sun.y - moon.y, sun.z - moon.z), axis: axis)
        var siteSun: [String: Double] = [:]
        for site in sites {
            let lat = radians(site.lat), lon = radians(site.lon)
            let normal = SIMD3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
            siteSun[site.id] = degrees(asin(simd_dot(normal, simd_normalize(sunDir))))
        }

        return SkySnapshot(
            date: date,
            altitude: horizon.altitude, azimuth: horizon.azimuth,
            illuminatedFraction: illumination.phase_fraction,
            librationLat: libration.elat, librationLon: libration.elon,
            polePositionAngle: poleAngle, parallacticAngle: parallactic,
            northFromUp: wrap180(poleAngle - parallactic),
            brightLimbFromUp: wrap180(brightLimb - parallactic),
            siteSunElevation: siteSun,
            moonrise: nextEvent(DIRECTION_RISE, after: date, observer: observer, lookBackHours: 12),
            moonset: nextEvent(DIRECTION_SET, after: date, observer: observer, lookBackHours: 0)
        )
    }

    /// Where a site falls on the disk as seen now, in units of the disk radius:
    /// `x` right and `y` up on screen. `nil` when it's on the far side.
    static func diskPoint(lat: Double, lon: Double, in sky: SkySnapshot) -> CGPoint? {
        let b0 = radians(sky.librationLat), l0 = radians(sky.librationLon)
        let φ = radians(lat), dλ = radians(lon) - l0
        let facing = sin(b0) * sin(φ) + cos(b0) * cos(φ) * cos(dλ)
        guard facing > 0 else { return nil }
        let east = cos(φ) * sin(dλ)
        let north = cos(b0) * sin(φ) - sin(b0) * cos(φ) * cos(dλ)
        // Turn lunar north to where it points on screen (counterclockwise from up).
        let θ = radians(sky.northFromUp)
        return CGPoint(x: east * cos(θ) - north * sin(θ), y: east * sin(θ) + north * cos(θ))
    }

    // MARK: Helpers

    private static func astroTime(_ date: Date) -> astro_time_t {
        // Astronomy Engine counts UT days from 2000-01-01 12:00 UTC.
        Astronomy_TimeFromDays((date.timeIntervalSince1970 - 946_728_000) / 86_400)
    }

    private static func date(from time: astro_time_t) -> Date {
        Date(timeIntervalSince1970: time.ut * 86_400 + 946_728_000)
    }

    private static func nextEvent(_ direction: astro_direction_t, after date: Date,
                                  observer: astro_observer_t, lookBackHours: Double) -> Date? {
        let start = astroTime(date.addingTimeInterval(-lookBackHours * 3600))
        let result = Astronomy_SearchRiseSetEx(BODY_MOON, observer, direction, start, 1.5, 0)
        return result.status == ASTRO_SUCCESS ? self.date(from: result.time) : nil
    }

    /// Position angle of a direction (ra2, dec2) around a center (ra1, dec1), east of north, in degrees.
    private static func positionAngle(ofRA ra2: Double, dec dec2: Double, fromRA ra1: Double, dec dec1: Double) -> Double {
        let a1 = radians(ra1), d1 = radians(dec1), a2 = radians(ra2), d2 = radians(dec2)
        let pa = atan2(cos(d2) * sin(a2 - a1), sin(d2) * cos(d1) - cos(d2) * sin(d1) * cos(a2 - a1))
        return (degrees(pa) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// J2000 equatorial vector to the Moon's body-fixed frame: R3(W) R1(90°-δ0) R3(90°+α0).
    private static func toMoonFixed(_ v: SIMD3<Double>, axis: astro_axis_t) -> SIMD3<Double> {
        rot3(rot1(rot3(v, 90 + axis.ra * 15), 90 - axis.dec), axis.spin)
    }

    private static func rot3(_ v: SIMD3<Double>, _ deg: Double) -> SIMD3<Double> {
        let c = cos(radians(deg)), s = sin(radians(deg))
        return SIMD3(c * v.x + s * v.y, -s * v.x + c * v.y, v.z)
    }

    private static func rot1(_ v: SIMD3<Double>, _ deg: Double) -> SIMD3<Double> {
        let c = cos(radians(deg)), s = sin(radians(deg))
        return SIMD3(v.x, c * v.y + s * v.z, -s * v.y + c * v.z)
    }

    private static func radians(_ d: Double) -> Double { d * .pi / 180 }
    private static func degrees(_ r: Double) -> Double { r * 180 / .pi }
    private static func wrap180(_ d: Double) -> Double {
        let x = (d + 180).truncatingRemainder(dividingBy: 360)
        return (x < 0 ? x + 360 : x) - 180
    }
}
