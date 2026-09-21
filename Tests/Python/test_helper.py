import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from types import SimpleNamespace

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


class AnnotationNormalizationTests(unittest.TestCase):
    @staticmethod
    def annotation(rows):
        return SimpleNamespace(itertracks=lambda **_: ((SimpleNamespace(start=s, end=e), None, label) for s, e, label in rows))

    def test_legacy_and_current_outputs_preserve_timestamps_and_speakers(self):
        annotation = self.annotation([(2, 3, "b"), (-0.1, 1, "a"), (4, 6, "a")])
        expected = [{"start": 0, "end": 1, "speaker": 0}, {"start": 2, "end": 3, "speaker": 1}, {"start": 4, "end": 5, "speaker": 0}]
        for result in [annotation, SimpleNamespace(speaker_diarization=annotation), SimpleNamespace(exclusive_speaker_diarization=annotation)]:
            self.assertEqual(helper.serialize_turns(result, 5), expected)

    def test_empty_exclusive_output_does_not_fall_back_to_overlapping_output(self):
        result = SimpleNamespace(exclusive_speaker_diarization=self.annotation([]), speaker_diarization=self.annotation([(0, 2, 'a')]))
        self.assertEqual(helper.serialize_turns(result, 3), [])

    def test_nonfinite_model_output_is_an_error(self):
        with self.assertRaises(ValueError):
            helper.serialize_turns(self.annotation([(0, float('nan'), 'a')]), 3)


if __name__ == '__main__':
    unittest.main()
