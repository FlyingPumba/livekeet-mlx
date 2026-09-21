import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

path = Path(__file__).parents[2] / 'Sources/LivekeetCore/Resources/Python/diarize.py'
spec = importlib.util.spec_from_file_location('helper', path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class HelperProtocolTests(unittest.TestCase):
    def invoke(self, lines, factory):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['diarize.py', 'wespeaker']):
            code = helper.serve(io.StringIO(lines), output, factory)
        return code, [json.loads(line) for line in output.getvalue().splitlines()]

    def test_models_load_once_and_requests_keep_state(self):
        loads = []
        def factory(name):
            loads.append(name)
            state = []
            def request(value):
                print('model diagnostic')
                state.append(value['channel'])
                return {'speaker': len(state) - 1}
            return request
        code, replies = self.invoke('{"channel":"mic"}\n{"channel":"system"}\n{"op":"quit"}\n', factory)
        self.assertEqual(code, 0)
        self.assertEqual(loads, ['wespeaker'])
        self.assertEqual(replies, [{'ok': True}, {'speaker': 0}, {'speaker': 1}])

    def test_startup_failure_is_actionable_json(self):
        def factory(_):
            raise ImportError('missing numpy')
        code, replies = self.invoke('', factory)
        self.assertEqual(code, 1)
        self.assertIn('scripts/setup-python.sh', replies[0]['error'])

    def test_request_errors_do_not_corrupt_protocol(self):
        code, replies = self.invoke('bad json\n{"channel":"mic"}\n', lambda _: lambda req: {'speaker': 2})
        self.assertEqual(code, 0)
        self.assertIn('error', replies[1])
        self.assertEqual(replies[2], {'speaker': 2})


if __name__ == '__main__':
    unittest.main()
