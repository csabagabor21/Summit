#!/usr/bin/env python3
"""Fókuszált teszt az aggregate.py viselkedésére (stdlib unittest, hálózat nélkül).

GDPR k-anonimitás: 6 főtől iskola nevével, 5 fő és alatta csak
városnévvel összevonva kerül ki a térképre.
Helyfeloldás: school_pins (kézi is) → Nominatim geokódolás → városlexikon.
Futtatás:  python3 -m unittest discover -s Firebase -p "test_*.py"
"""
import unittest

import aggregate

MATHIASZ = "Siófoki SZC Mathiász János Technikum és Gimnázium"

# Valódi Nominatim-válasz (jsonv2) a Mathiász-iskolára, konzervnek.
MATHIASZ_HITS = [{
    "osm_type": "relation",
    "lat": "46.7753108",
    "lon": "17.6582736",
    "category": "amenity",
    "type": "school",
    "name": MATHIASZ,
    "display_name": (MATHIASZ + ", 41, Szabadság utca, Balatonboglár, Fonyódi járás, "
                     "Somogy vármegye, Dél-Dunántúl, Dunántúl, 8630, Magyarország"),
    "address": {"amenity": MATHIASZ, "house_number": "41", "road": "Szabadság utca",
                "town": "Balatonboglár", "municipality": "Fonyódi járás",
                "county": "Somogy vármegye", "postcode": "8630",
                "country": "Magyarország", "country_code": "hu"},
}]


def canned(mapping):
    """fetch-helyettes: lekérdezés -> konzerv találatlista, és naplózza a hívásokat."""
    calls = []

    def fetch(query):
        calls.append(query)
        return mapping.get(query, [])

    fetch.calls = calls
    return fetch


class TestSchoolNameThreshold(unittest.TestCase):
    def test_threshold_is_six(self):
        self.assertEqual(aggregate.SCHOOL_NAME_THRESHOLD, 6)

    def test_six_shows_school_name(self):
        self.assertTrue(aggregate.shows_school_name(6))

    def test_five_or_fewer_city_only(self):
        self.assertFalse(aggregate.shows_school_name(5))
        self.assertFalse(aggregate.shows_school_name(1))
        self.assertFalse(aggregate.shows_school_name(0))


class TestCityGrouping(unittest.TestCase):
    def setUp(self):
        self.alias = aggregate.aliases()

    def test_big_school_keeps_name(self):
        out = aggregate.build_public_entries([{
            "display": "Debreceni Ady Endre Gimnázium", "city": "Debrecen",
            "lon": 21.63, "lat": 47.53, "count": 7}])
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["name"], "Debreceni Ady Endre Gimnázium")
        self.assertEqual(out[0]["count"], 7)

    def test_small_schools_merge_by_city(self):
        out = aggregate.build_public_entries([
            {"display": "Siófoki A Iskola", "city": "Siófok",
             "lon": 18.05, "lat": 46.91, "count": 2},
            {"display": "Siófoki B Iskola", "city": "Siófok",
             "lon": 18.05, "lat": 46.91, "count": 3}])
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["name"], "Siófok")
        self.assertEqual(out[0]["count"], 5)
        self.assertEqual((out[0]["lon"], out[0]["lat"]),
                         aggregate.GAZETTEER["Siófok"])

    def test_small_school_name_never_leaks(self):
        out = aggregate.build_public_entries([{
            "display": "Siófoki Kis Iskola", "city": "Siófok",
            "lon": 18.05, "lat": 46.91, "count": 1}])
        names = [e["name"] for e in out]
        self.assertNotIn("Siófoki Kis Iskola", names)

    def test_cityless_small_school_dropped(self):
        out = aggregate.build_public_entries([{
            "display": "Ismeretlen Iskola", "city": None,
            "lon": 0.0, "lat": 0.0, "count": 2}])
        self.assertEqual(out, [])

    def test_small_school_uses_geocoded_city_not_name_city(self):
        """k<6: a geokódolt (valódi) város látszik, nem a névből kitalált."""
        pin = aggregate.make_pin(17.6583, 46.7753, "Balatonboglár", "nominatim")
        city = aggregate.resolve_city(MATHIASZ, pin, self.alias)
        self.assertEqual(city, "Balatonboglár")
        out = aggregate.build_public_entries([{
            "display": MATHIASZ, "city": city,
            "lon": pin["lon"], "lat": pin["lat"], "count": 3}])
        self.assertEqual([e["name"] for e in out], ["Balatonboglár"])
        self.assertNotIn("Siófok", [e["name"] for e in out])

    def test_city_outside_gazetteer_needs_position(self):
        """Lexikonon kívüli város csak megadott koordinátával kerül ki."""
        items = [{"display": "Valami Iskola", "city": "Bugyi",
                  "lon": 19.15, "lat": 47.22, "count": 2}]
        self.assertEqual(aggregate.build_public_entries(items), [])
        out = aggregate.build_public_entries(items, {"Bugyi": (19.15, 47.22)})
        self.assertEqual(out[0]["name"], "Bugyi")
        self.assertEqual((out[0]["lon"], out[0]["lat"]), (19.15, 47.22))

    def test_resolve_city_from_name_when_no_pin_city(self):
        self.assertEqual(
            aggregate.resolve_city("Debreceni Ady Endre Gimnázium", None, self.alias),
            "Debrecen")

    def test_resolve_city_pin_wins_over_name(self):
        pin = aggregate.make_pin(17.65, 46.77, "Balatonboglár", "manual")
        self.assertEqual(
            aggregate.resolve_city("Siófoki Valami Iskola", pin, self.alias),
            "Balatonboglár")

    def test_resolve_city_unknown_is_none(self):
        self.assertIsNone(
            aggregate.resolve_city("Kitalált Falusi Iskola", None, self.alias))


class TestGeocoding(unittest.TestCase):
    def test_queries_get_progressively_simpler(self):
        qs = aggregate.geocode_queries(MATHIASZ)
        self.assertEqual(qs[0], MATHIASZ)
        self.assertEqual(qs[1], "Mathiász János Technikum és Gimnázium")
        self.assertEqual(qs[-1], "Mathiász János")

    def test_key_words_drop_type_and_city_words(self):
        self.assertEqual(aggregate.key_words(MATHIASZ), ["Mathiász", "János"])

    def test_mathiasz_geocodes_to_balatonboglar(self):
        fetch = canned({MATHIASZ: MATHIASZ_HITS})
        pin = aggregate.geocode_school(MATHIASZ, fetch=fetch)
        self.assertEqual(pin["city"], "Balatonboglár")
        self.assertAlmostEqual(pin["lon"], 17.6583, places=3)
        self.assertAlmostEqual(pin["lat"], 46.7753, places=3)
        self.assertEqual(pin["source"], "nominatim")
        self.assertEqual(fetch.calls, [MATHIASZ])  # az első kérdés elég volt

    def test_falls_back_to_simpler_query(self):
        fetch = canned({"Mathiász János Technikum és Gimnázium": MATHIASZ_HITS})
        pin = aggregate.geocode_school(MATHIASZ, fetch=fetch)
        self.assertEqual(pin["city"], "Balatonboglár")
        self.assertEqual(len(fetch.calls), 2)

    def test_no_hit_returns_none_after_all_queries(self):
        fetch = canned({})
        self.assertIsNone(aggregate.geocode_school(MATHIASZ, fetch=fetch))
        self.assertEqual(len(fetch.calls), 3)

    def test_outside_hungary_rejected(self):
        far = [dict(MATHIASZ_HITS[0], lat="48.8566", lon="2.3522")]  # Párizs
        self.assertFalse(aggregate.in_hungary(2.3522, 48.8566))
        self.assertTrue(aggregate.in_hungary(17.65, 46.77))
        self.assertIsNone(aggregate.geocode_school(MATHIASZ, fetch=canned({MATHIASZ: far})))

    def test_irrelevant_hit_rejected(self):
        junk = [{"lat": "47.5", "lon": "19.04", "category": "shop", "type": "bakery",
                 "display_name": "Pékség, Budapest", "address": {"city": "Budapest"}}]
        self.assertIsNone(aggregate.pick_pin(junk, MATHIASZ))

    def test_city_never_a_jaras_or_varmegye(self):
        hit = {"address": {"municipality": "Fonyódi járás", "county": "Somogy vármegye"}}
        self.assertIsNone(aggregate.hit_city(hit))

    def test_geocoder_respects_per_run_limit(self):
        fetch = canned({MATHIASZ: MATHIASZ_HITS})
        geocode = aggregate.make_geocoder(limit=1, fetch=fetch, log=lambda *_: None)
        self.assertIsNotNone(geocode(MATHIASZ))
        self.assertIsNone(geocode(MATHIASZ))  # elfogyott a keret, nem hálózik
        self.assertEqual(len(fetch.calls), 1)


class TestPinResolution(unittest.TestCase):
    def setUp(self):
        self.alias = aggregate.aliases()
        self.fetch = canned({MATHIASZ: MATHIASZ_HITS})
        self.geocode = aggregate.make_geocoder(fetch=self.fetch, log=lambda *_: None)

    def test_manual_pin_wins_and_blocks_geocoding(self):
        manual = {MATHIASZ: aggregate.make_pin(1.0, 2.0, "Kézi Város", "manual")}
        pin = aggregate.resolve_pin(MATHIASZ, manual, self.alias, self.geocode)
        self.assertEqual((pin["lon"], pin["lat"]), (1.0, 2.0))
        self.assertEqual(pin["source"], "manual")
        self.assertEqual(self.fetch.calls, [])  # meglévő pin mellett nincs hálózás

    def test_geocoding_wins_over_gazetteer(self):
        pin = aggregate.resolve_pin(MATHIASZ, {}, self.alias, self.geocode)
        self.assertEqual(pin["source"], "nominatim")
        self.assertEqual(pin["city"], "Balatonboglár")
        self.assertNotEqual((pin["lon"], pin["lat"]), aggregate.GAZETTEER["Siófok"])

    def test_gazetteer_is_last_resort(self):
        empty = aggregate.make_geocoder(fetch=canned({}), log=lambda *_: None)
        pin = aggregate.resolve_pin("Debreceni Ady Endre Gimnázium", {}, self.alias, empty)
        self.assertEqual(pin["source"], "gazetteer")
        self.assertEqual(pin["city"], "Debrecen")
        self.assertEqual((pin["lon"], pin["lat"]), aggregate.GAZETTEER["Debrecen"])

    def test_pin_from_directory_wins(self):
        pins = {"Valami Gimnázium": aggregate.make_pin(1.0, 2.0, None, "manual")}
        pin = aggregate.resolve_pin("Valami Gimnázium", pins, self.alias)
        self.assertEqual((pin["lon"], pin["lat"]), (1.0, 2.0))

    def test_pin_from_city_alias_without_geocoder(self):
        pin = aggregate.resolve_pin("Debreceni Ady Endre Gimnázium", {}, self.alias)
        self.assertEqual((pin["lon"], pin["lat"]), aggregate.GAZETTEER["Debrecen"])

    def test_unknown_city_returns_none(self):
        empty = aggregate.make_geocoder(fetch=canned({}), log=lambda *_: None)
        self.assertIsNone(
            aggregate.resolve_pin("Kitalált Falusi Iskola", {}, self.alias, empty))


class TestCodeResolution(unittest.TestCase):
    def setUp(self):
        self.alias = aggregate.aliases()
        self.fetch = canned({MATHIASZ: MATHIASZ_HITS})
        self.geocode = aggregate.make_geocoder(fetch=self.fetch, log=lambda *_: None)

    def test_empty_name_known_code_resolves(self):
        res = aggregate.resolve_school("", "siszc-mathiasz", {}, self.alias, self.geocode)
        self.assertIsNotNone(res)
        self.assertIn("Mathiász", res[0])

    def test_code_resolves_to_balatonboglar_not_siofok(self):
        _, pin = aggregate.resolve_school("", "siszc-mathiasz", {}, self.alias, self.geocode)
        self.assertEqual(pin["city"], "Balatonboglár")
        self.assertAlmostEqual(pin["lon"], 17.66, places=1)
        self.assertAlmostEqual(pin["lat"], 46.78, places=1)

    def test_code_like_name_resolves(self):
        res = aggregate.resolve_school("siszc-mathiasz", "siszc-mathiasz", {},
                                       self.alias, self.geocode)
        self.assertIsNotNone(res)
        self.assertIn("Mathiász", res[0])

    def test_real_name_still_wins_over_code(self):
        res = aggregate.resolve_school(
            "Debreceni Ady Endre Gimnázium", "klik000000001", {}, self.alias)
        self.assertIsNotNone(res)
        self.assertIn("Debreceni", res[0])

    def test_unknown_code_returns_none(self):
        self.assertIsNone(aggregate.resolve_school("", "klik999999999", {}, self.alias))
        self.assertIsNone(aggregate.resolve_school("", "", {}, self.alias))


class TestPinStorage(unittest.TestCase):
    def test_read_pins_old_docs_count_as_manual(self):
        docs = [{"name": "p/1", "fields": {
            "name": {"stringValue": "Régi Iskola"},
            "lon": {"doubleValue": 19.0}, "lat": {"doubleValue": 47.0}}}]
        pins = aggregate.read_pins(docs)
        self.assertEqual(pins["Régi Iskola"]["source"], "manual")
        self.assertIsNone(pins["Régi Iskola"]["city"])

    def test_read_pins_keeps_city_and_source(self):
        docs = [{"name": "p/2", "fields": {
            "name": {"stringValue": MATHIASZ},
            "lon": {"doubleValue": 17.6583}, "lat": {"doubleValue": 46.7753},
            "city": {"stringValue": "Balatonboglár"},
            "source": {"stringValue": "nominatim"}}}]
        pin = aggregate.read_pins(docs)[MATHIASZ]
        self.assertEqual(pin["city"], "Balatonboglár")
        self.assertEqual(pin["source"], "nominatim")

    def test_read_pins_skips_broken_docs(self):
        docs = [{"name": "p/3", "fields": {"name": {"stringValue": "Csonka"}}}]
        self.assertEqual(aggregate.read_pins(docs), {})

    def test_pin_body_is_backwards_compatible(self):
        body = aggregate.pin_body(MATHIASZ, aggregate.make_pin(
            17.6583, 46.7753, "Balatonboglár", "nominatim"))
        f = body["fields"]
        self.assertEqual(f["name"]["stringValue"], MATHIASZ)
        self.assertEqual(f["lon"]["doubleValue"], 17.6583)
        self.assertEqual(f["lat"]["doubleValue"], 46.7753)
        self.assertEqual(f["city"]["stringValue"], "Balatonboglár")
        self.assertEqual(f["source"]["stringValue"], "nominatim")


if __name__ == "__main__":
    unittest.main()
