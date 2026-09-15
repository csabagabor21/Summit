#!/usr/bin/env python3
"""Fókuszált teszt az aggregate.py viselkedésére (stdlib unittest).

GDPR k-anonimitás: 6 főtől iskola nevével, 5 fő és alatta csak
városnévvel összevonva kerül ki a térképre.
Futtatás:  python3 -m unittest discover -s Firebase -p "test_*.py"
"""
import unittest

import aggregate


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

    def test_resolve_city_from_name(self):
        self.assertEqual(
            aggregate.resolve_city("Debreceni Ady Endre Gimnázium", "", self.alias),
            "Debrecen")

    def test_resolve_city_from_code(self):
        self.assertEqual(
            aggregate.resolve_city("", "siszc-mathiasz", self.alias), "Siófok")

    def test_resolve_city_unknown_is_none(self):
        self.assertIsNone(
            aggregate.resolve_city("Kitalált Falusi Iskola", "", self.alias))


class TestPinResolution(unittest.TestCase):
    def setUp(self):
        self.alias = aggregate.aliases()

    def test_pin_from_directory_wins(self):
        hit = aggregate.resolve_pin("Valami Gimnázium", {"Valami Gimnázium": (1.0, 2.0)}, self.alias)
        self.assertEqual(hit, (1.0, 2.0))

    def test_pin_from_city_alias(self):
        hit = aggregate.resolve_pin("Debreceni Ady Endre Gimnázium", {}, self.alias)
        self.assertEqual(hit, aggregate.GAZETTEER["Debrecen"])

    def test_unknown_city_returns_none(self):
        self.assertIsNone(aggregate.resolve_pin("Kitalált Falusi Iskola", {}, self.alias))


class TestCodeResolution(unittest.TestCase):
    def setUp(self):
        self.alias = aggregate.aliases()

    def test_empty_name_known_code_resolves(self):
        res = aggregate.resolve_school("", "siszc-mathiasz", {}, self.alias)
        self.assertIsNotNone(res)
        self.assertIn("Mathiász", res[0])

    def test_code_like_name_resolves(self):
        res = aggregate.resolve_school("siszc-mathiasz", "siszc-mathiasz", {}, self.alias)
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


if __name__ == "__main__":
    unittest.main()
