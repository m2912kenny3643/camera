import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('simulator', Path(__file__).with_name('prepare_simulator.py'))
simulator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulator)

class SimulatorTests(unittest.TestCase):
    def testFallsBackOnlyFromIncompatibleRuntime(self):
        runtimes = [dict(version='27.0', identifier='ios27'), dict(version='27.1', identifier='ios271')]
        results = [subprocess.CompletedProcess([], 147, '', 'Incompatible device'),
                   subprocess.CompletedProcess([], 0, 'test-udid\n', '')]
        with patch.object(simulator.subprocess, 'run', side_effect=results) as run:
            udid, runtime = simulator.create_compatible_simulator('iphone17', runtimes)
        self.assertEqual(udid, 'test-udid')
        self.assertEqual(runtime['version'], '27.0')
        self.assertEqual(run.call_args_list[0].args[0][-1], 'ios271')
        self.assertEqual(run.call_args_list[1].args[0][-1], 'ios27')

    def testDoesNotHideUnrelatedCreationFailures(self):
        with patch.object(simulator.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'disk full')) as run:
            with self.assertRaisesRegex(RuntimeError, 'disk full'):
                simulator.create_compatible_simulator('iphone17', [dict(version='27.0', identifier='ios27')])
            self.assertEqual(run.call_count, 1)

    def testAllIncompatibleIsExplicitFailure(self):
        with patch.object(simulator.subprocess, 'run', return_value=subprocess.CompletedProcess([], 147, '', 'Incompatible device')):
            with self.assertRaisesRegex(RuntimeError, 'No compatible'):
                simulator.create_compatible_simulator('iphone17', [dict(version='27.0', identifier='ios27')])

if __name__ == '__main__': unittest.main()
