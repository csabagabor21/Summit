#!/usr/bin/env python3
"""Fókuszált teszt az aggregate.py viselkedésére (stdlib unittest).

A nyilvános küszöb változását őrzi: 1 fős iskola is kikerül a térképre.
Futtatás:  python3 -m unittest discover -s Firebase -p "test_*.py"
"""
import unittest

import aggregate


class TestPublicThreshold(unittest.TestCase):
    def test_no_threshold_single_user_counts(self):
        self.assertEqual(aggregate.PUBLIC_THRESHOLD, 1)
        self.assertTrue(aggregate.passes_threshold({"install-1"}))

    def test_empty_set_excluded(self):
        self.assertFalse(aggregate.passes_threshold(set()))


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


if __name__ == "__main__":
    unittest.main()
