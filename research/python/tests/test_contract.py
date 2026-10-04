import json
import pathlib
import unittest

from stack_chess.contract import action_from_dict, action_to_dict, state_from_dict, state_to_dict
from stack_chess.engine import apply_action, legal_actions, validate_state


FIXTURES = pathlib.Path(__file__).parents[3] / "fixtures"


class ContractTests(unittest.TestCase):
    def test_development_fixture_replays_in_python(self):
        fixture = json.loads((FIXTURES / "development_opening.json").read_text())
        state = state_from_dict(fixture["initial_state"])
        for step in fixture["steps"]:
            action = action_from_dict(step["action"])
            self.assertIn(action, legal_actions(state))
            state = apply_action(state, action)
            self.assertEqual(state.ply, step["expected"]["ply"])
            self.assertEqual(state.turn.value, step["expected"]["turn"])
        validate_state(state, enforce_inventory=True)
        exported = state_to_dict(state)
        self.assertEqual(exported["contract_version"], 2)
        self.assertIn("reinforcement", json.dumps(exported))

    def test_contract_v1_state_is_rejected(self):
        fixture = json.loads((FIXTURES / "development_opening.json").read_text())
        fixture["initial_state"]["contract_version"] = 1
        with self.assertRaisesRegex(ValueError, "unsupported contract version"):
            state_from_dict(fixture["initial_state"])


if __name__ == "__main__":
    unittest.main()
