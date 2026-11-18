"""Offline-Tests fuer weather.py (kein Netz noetig): python3 -I -m unittest discover -s tests"""
import io, json, os, sys, unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plugin"))
import weather  # noqa: E402


class Coords(unittest.TestCase):
    def test_gueltig(self):
        self.assertEqual(weather.coords("47.27", "11.40"), (47.27, 11.40))

    def test_ausserhalb(self):
        for bad in (("91", "0"), ("0", "181"), ("nan", "0")):
            with self.assertRaises(ValueError):
                weather.coords(*bad)

    def test_kein_zahlenwert(self):
        with self.assertRaises(ValueError):
            weather.coords("x", "1")


class Get(unittest.TestCase):
    def test_nur_https(self):
        with self.assertRaises(ValueError):
            weather.get("http://example.org/")

    def test_zu_gross(self):
        big = io.BytesIO(b"x" * (weather.MAX_BYTES + 10))
        with mock.patch("urllib.request.urlopen") as op:
            op.return_value.__enter__.return_value = big
            with self.assertRaises(ValueError):
                weather.get("https://example.org/")


class Icons(unittest.TestCase):
    def test_nacht_klar_ist_mond(self):
        self.assertEqual(weather.icon(0, night=True)[0], weather.ICONS["moon"])

    def test_unbekannter_code(self):
        self.assertEqual(weather.icon(12345)[1], "Unbekannt")


class Foehn(unittest.TestCase):
    def test_differenz(self):
        with mock.patch.object(weather, "get", return_value={"current": {"pressure_msl": 1006.4}}):
            self.assertEqual(weather.foehn(1002.1), {"bozen": 1006.4, "innsbruck": 1002.1, "diff": 4.3})

    def test_fehler_gibt_none(self):
        with mock.patch.object(weather, "get", side_effect=OSError("offline")):
            self.assertIsNone(weather.foehn(1002.1))


if __name__ == "__main__":
    unittest.main()
