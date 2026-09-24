"""Exercise identity persistence without touching the user's keychain or settings."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'sign-local-app.sh'
FIRST = 'A' * 40
SECOND = 'B' * 40


class LocalSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.identity_file = self.root / 'config' / 'signing-identity'
        self.log = self.root / 'codesign.log'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.tool('security', 'printf "%s\\n" "$TEST_IDENTITIES"')
        self.tool('codesign', 'printf "%s\\n" "$*" >> "$TEST_CODESIGN_LOG"\nexit "${TEST_CODESIGN_EXIT:-0}"')

    def tool(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_signing(self, identities, requested='', fail=False):
        env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                   LIVEKEET_SIGNING_IDENTITY_FILE=str(self.identity_file),
                   SIGNING_IDENTITY=requested, TEST_IDENTITIES=identities,
                   TEST_CODESIGN_LOG=str(self.log), TEST_CODESIGN_EXIT='1' if fail else '0')
        return subprocess.run(['/bin/bash', str(SCRIPT), '/tmp/test app.app', '/tmp/entitlements.plist'],
                              env=env, text=True, capture_output=True)

    def test_single_certificate_is_pinned_and_reused_when_others_appear(self):
        first = f'  1) {FIRST} "Local Developer"\n     1 valid identities found'
        result = self.run_signing(first)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.identity_file.read_text().strip(), FIRST)
        result = self.run_signing(f'  1) {SECOND} "Another certificate"\n  2) {FIRST} "Local Developer"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(SECOND, self.log.read_text())

    def test_missing_pinned_certificate_never_changes_identity(self):
        self.identity_file.parent.mkdir()
        self.identity_file.write_text(FIRST + '\n')
        result = self.run_signing(f'  1) {SECOND} "Other certificate"')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.identity_file.read_text().strip(), FIRST)

    def test_no_certificate_or_ambiguous_selection_does_not_sign(self):
        for identities in ['     0 valid identities found',
                           f'  1) {FIRST} "First"\n  2) {SECOND} "Second"']:
            result = self.run_signing(identities)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.log.exists())
            self.assertFalse(self.identity_file.exists())

    def test_explicit_name_is_saved_as_fingerprint_only_after_success(self):
        identities = f'  1) {FIRST} "First"\n  2) {SECOND} "Second"'
        result = self.run_signing(identities, 'Second', fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.identity_file.exists())
        result = self.run_signing(identities, 'Second')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.identity_file.read_text().strip(), SECOND)

    def test_explicit_adhoc_build_does_not_replace_pinned_certificate(self):
        self.identity_file.parent.mkdir()
        self.identity_file.write_text(FIRST + '\n')
        result = self.run_signing('', '-')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('permissions may reset', result.stderr)
        self.assertEqual(self.identity_file.read_text().strip(), FIRST)
        self.assertIn('--sign - --entitlements', self.log.read_text())


if __name__ == '__main__':
    unittest.main()
