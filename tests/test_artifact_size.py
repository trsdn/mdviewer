import importlib.util
import pathlib
import sys
import unittest


sys.dont_write_bytecode = True
SCRIPT = pathlib.Path(__file__).parents[1] / "scripts/check_artifact_size.py"
SPEC = importlib.util.spec_from_file_location("check_artifact_size", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ArtifactSizeLimitTests(unittest.TestCase):
    def test_release_build_enables_xcode_postprocessing(self):
        project = (SCRIPT.parents[1] / "project.yml").read_text()
        self.assertEqual(project.count("DEPLOYMENT_POSTPROCESSING: true"), 2)
        self.assertIn("STRIP_INSTALLED_PRODUCT: true", project)

    def test_requires_both_limits_to_be_exceeded(self):
        baseline = 30_000_000
        self.assertFalse(MODULE.exceeds_limit(baseline + 524_288, baseline))
        self.assertFalse(MODULE.exceeds_limit(baseline + 524_289, baseline))
        self.assertTrue(MODULE.exceeds_limit(baseline + 600_001, baseline))

    def test_two_percent_boundary_is_strict(self):
        baseline = 10_000_000
        self.assertFalse(MODULE.exceeds_limit(baseline + 524_288, baseline))
        self.assertTrue(MODULE.exceeds_limit(baseline + 524_289, baseline))


if __name__ == "__main__":
    unittest.main()
