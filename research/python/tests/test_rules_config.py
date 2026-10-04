import unittest

from stack_chess.engine import (
    ATTRITION_CONTROL_RULES,
    ATTRITION_DEVELOPMENT_RULES,
    ATTRITION_DEVELOPMENT_INFILTRATION_RULES,
    CATALOG_HASH,
    CONTROL_RULES,
    DEVELOPMENT_RULES,
    DEVELOPMENT_INFILTRATION_RULES,
    PIECE_CONFIG,
    STARTING_COUNTS,
    PieceType,
)
from stack_chess.rules_config import CATALOG


class SharedRuleConfigurationTests(unittest.TestCase):
    def test_catalog_identity_and_inventory(self):
        self.assertEqual(CATALOG["id"], "core-pieces-v3")
        self.assertTrue(CATALOG["specials"]["sovereign"]["royal_attack"])
        self.assertEqual(len(CATALOG_HASH), 64)
        self.assertEqual(STARTING_COUNTS[PieceType.INFANTRY], 9)
        self.assertEqual(set(PIECE_CONFIG), set(PieceType))
        self.assertEqual(PIECE_CONFIG[PieceType.SOVEREIGN]["notation"], "V")
        self.assertEqual(PIECE_CONFIG[PieceType.SPY]["notation"], "Sp")
        self.assertEqual(PIECE_CONFIG[PieceType.RECALL]["notation"], "Rc")
        self.assertEqual(PIECE_CONFIG[PieceType.REINFORCEMENT]["notation"], "Rf")

    def test_corrected_griffin_vectors_come_from_catalog(self):
        vectors = PIECE_CONFIG[PieceType.GRIFFIN]["movement"]["vectors_by_height"]
        self.assertEqual(vectors["1"], [[1, 2], [2, 1]])
        self.assertEqual(vectors["2"], [[1, 2], [2, 1]])
        self.assertEqual(vectors["3"], [[2, 3], [3, 2]])

    def test_rulesets_reference_same_catalog(self):
        self.assertEqual(CONTROL_RULES.id, "control-v3")
        self.assertEqual(DEVELOPMENT_RULES.id, "development-v3")
        self.assertEqual(CONTROL_RULES.catalog_hash, CATALOG_HASH)
        self.assertEqual(DEVELOPMENT_RULES.catalog_hash, CATALOG_HASH)
        self.assertEqual(CONTROL_RULES.move_vs_taller, "illegal")
        self.assertEqual(ATTRITION_CONTROL_RULES.move_vs_taller, "mutual_bottom_attrition")
        self.assertEqual(ATTRITION_DEVELOPMENT_RULES.artillery_vs_taller, "target_bottom_attrition")
        self.assertFalse(DEVELOPMENT_RULES.infiltration_victory)
        self.assertTrue(DEVELOPMENT_INFILTRATION_RULES.infiltration_victory)
        self.assertTrue(ATTRITION_DEVELOPMENT_INFILTRATION_RULES.infiltration_victory)


if __name__ == "__main__":
    unittest.main()
