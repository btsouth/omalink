#!/usr/bin/python3
import importlib.machinery
import importlib.util
import pathlib
import subprocess
import sys
import unittest


sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/omalink-mfa"
loader = importlib.machinery.SourceFileLoader("omalink_mfa", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
mfa = importlib.util.module_from_spec(spec)
loader.exec_module(mfa)


class MfaDetection(unittest.TestCase):
    def test_authentication_codes(self):
        cases = {
            "Your verification code is 123456. Expires in 10 minutes.": "123456",
            "123456 is your sign-in code": "123456",
            "Security code: 4821": "4821",
            "Use one-time code 123 456 to continue": "123456",
            "OTP 12345678": "12345678",
            "Your code is 004219": "004219",
            "Microsoft Authenticator\nYour code: 349871": "349871",
        }
        for message, expected in cases.items():
            with self.subTest(message=message):
                self.assertEqual(mfa.extract(message), expected)

    def test_ambiguous_or_unrelated_text(self):
        cases = [
            "Dinner at 1234 Main Street",
            "Your order code: 123456",
            "Promo code: 123456",
            "Security alert: transaction $123456 was approved",
            "Your verification code is 123456, or use backup code 987654",
            "Account 123456: your verification code is 654321",
            "Your verification code is 123456789",
            "Your verification code is ab123456cd",
            "Sensitive notification content hidden. Your code is 123456",
            "Your verification code is " + "x" * 70 + "123456",
            "Authenticator\n123456",
        ]
        for message in cases:
            with self.subTest(message=message[:80]):
                self.assertIsNone(mfa.extract(message))

    def test_private_stdin_contract(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], input=b"Your code is 004219",
                                capture_output=True, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"004219\n")
        self.assertEqual(result.stderr, b"")
        result = subprocess.run([sys.executable, str(SCRIPT)], input=b"Hello", capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
