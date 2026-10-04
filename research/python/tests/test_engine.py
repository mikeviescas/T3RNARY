import random
import unittest
from collections import Counter

from stack_chess.engine import (
    ATTRITION_CONTROL_RULES,
    ATTRITION_DEVELOPMENT_INFILTRATION_RULES,
    DEVELOPMENT_RULES,
    GameState,
    MoveAction,
    Piece,
    PieceType as T,
    PlaceAction,
    Player as P,
    RecallAction,
    apply_action,
    initial_state,
    is_sovereign_threatened,
    legal_actions,
    parse_square as sq,
    validate_state,
)


def pc(owner, kind):
    return Piece(owner, kind)


def state_with(board, turn=P.WHITE, reserves=None, discards=None, rules=None):
    return GameState(
        board={sq(name): tuple(stack) for name, stack in board.items()},
        reserves=reserves or {P.WHITE: Counter(), P.BLACK: Counter()},
        discards=discards or {P.WHITE: Counter(), P.BLACK: Counter()},
        turn=turn,
        rules=rules or GameState().rules,
    )


class InitialStateTests(unittest.TestCase):
    def test_development_opening_accepts_variable_back_rank_sovereigns(self):
        state = initial_state(DEVELOPMENT_RULES, sovereign_files=(0, 8))
        self.assertEqual(state.board[sq("A1")][-1].kind, T.SOVEREIGN)
        self.assertEqual(state.board[sq("I9")][-1].kind, T.SOVEREIGN)
        self.assertNotIn(sq("E1"), state.board)
        self.assertNotIn(sq("E9"), state.board)

    def test_standard_formation_and_inventory(self):
        state = initial_state()
        self.assertEqual(state.board[sq("E1")][-1], pc(P.WHITE, T.SOVEREIGN))
        self.assertEqual(state.board[sq("E9")][-1], pc(P.BLACK, T.SOVEREIGN))
        self.assertEqual(state.reserves[P.WHITE][T.INFANTRY], 6)
        self.assertEqual(sum(state.reserves[P.WHITE].values()), 23)
        validate_state(state, enforce_inventory=True)

    def test_development_opening_starts_with_only_fixed_sovereigns(self):
        state = initial_state(DEVELOPMENT_RULES)
        self.assertEqual(set(state.board), {sq("E1"), sq("E9")})
        self.assertTrue(state.in_development)
        self.assertEqual(sum(state.reserves[P.WHITE].values()), 26)
        actions = legal_actions(state)
        self.assertTrue(actions)
        self.assertFalse([action for action in actions if isinstance(action, MoveAction)])
        self.assertFalse(
            [
                action
                for action in actions
                if action.piece in {T.SPY, T.BALLISTA, T.TREBUCHET, T.RECALL}
            ]
        )
        self.assertTrue(all(action.destination[1] <= 2 for action in actions))

    def test_development_ends_after_four_extra_placements_each(self):
        state = initial_state(DEVELOPMENT_RULES)
        sequence = (
            PlaceAction(T.INFANTRY, sq("A1")),
            PlaceAction(T.INFANTRY, sq("A9")),
            PlaceAction(T.CHARIOT, sq("B1")),
            PlaceAction(T.CHARIOT, sq("B9")),
            PlaceAction(T.INFANTRY, sq("A2")),
            PlaceAction(T.INFANTRY, sq("A8")),
            PlaceAction(T.GRIFFIN, sq("B2")),
            PlaceAction(T.GRIFFIN, sq("B8")),
        )
        for index, action in enumerate(sequence):
            self.assertIn(action, legal_actions(state))
            state = apply_action(state, action)
            self.assertEqual(state.in_development, index < len(sequence) - 1)
        self.assertEqual(state.turn, P.WHITE)
        self.assertTrue([action for action in legal_actions(state) if isinstance(action, MoveAction)])

    def test_nonsovereign_move_unlocks_height_three(self):
        state = initial_state(DEVELOPMENT_RULES)
        state.development_placements = {P.WHITE: 4, P.BLACK: 4}
        state.board[sq("A1")] = (pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.CHARIOT))
        state.board[sq("C1")] = (pc(P.WHITE, T.INFANTRY),)
        state.reserves[P.WHITE][T.INFANTRY] -= 2
        state.reserves[P.WHITE][T.CHARIOT] -= 1
        self.assertNotIn(PlaceAction(T.MARSHAL, sq("A1")), legal_actions(state))
        state = apply_action(state, MoveAction(sq("C1"), sq("C2")))
        state.turn = P.WHITE
        self.assertTrue(state.height_three_unlocked[P.WHITE])
        self.assertIn(PlaceAction(T.MARSHAL, sq("A1")), legal_actions(state))


class MovementTests(unittest.TestCase):
    def test_infiltration_wins_immediately_on_enemy_back_row(self):
        state = state_with(
            {
                "E8": [pc(P.WHITE, T.SOVEREIGN)],
                "A9": [pc(P.BLACK, T.MARSHAL)],
                "E1": [pc(P.BLACK, T.SOVEREIGN)],
            },
            rules=ATTRITION_DEVELOPMENT_INFILTRATION_RULES,
        )
        state.development_placements = {P.WHITE: 4, P.BLACK: 4}
        action = MoveAction(sq("E8"), sq("E9"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertEqual(result.winner, P.WHITE)
        self.assertTrue(result.is_over)

    def test_back_row_is_not_a_win_in_capture_only_rules(self):
        state = state_with(
            {"E8": [pc(P.WHITE, T.SOVEREIGN)], "E1": [pc(P.BLACK, T.SOVEREIGN)]},
            rules=ATTRITION_CONTROL_RULES,
        )
        result = apply_action(state, MoveAction(sq("E8"), sq("E9")))
        self.assertIsNone(result.winner)

    def test_royal_attack_removes_entire_taller_stack_and_occupies(self):
        state = state_with(
            {
                "E4": [pc(P.WHITE, T.SOVEREIGN)],
                "E5": [
                    pc(P.BLACK, T.REINFORCEMENT),
                    pc(P.BLACK, T.INFANTRY),
                    pc(P.BLACK, T.MARSHAL),
                ],
            },
            rules=ATTRITION_CONTROL_RULES,
        )
        action = MoveAction(sq("E4"), sq("E5"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertEqual(result.board[sq("E5")], (pc(P.WHITE, T.SOVEREIGN),))
        self.assertNotIn(sq("E4"), result.board)
        self.assertEqual(sum(result.discards[P.BLACK].values()), 3)
        self.assertEqual(result.discards[P.WHITE][T.SOVEREIGN], 0)

    def test_protected_royal_attack_is_legal_but_leaves_sovereign_threatened(self):
        state = state_with(
            {
                "E4": [pc(P.WHITE, T.SOVEREIGN)],
                "E5": [pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.CHARIOT)],
                "E7": [pc(P.BLACK, T.MARSHAL)],
            },
            rules=ATTRITION_CONTROL_RULES,
        )
        action = MoveAction(sq("E4"), sq("E5"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertTrue(is_sovereign_threatened(result, P.WHITE))

    def test_infantry_moves_forward_by_height_and_cannot_pass_blocker(self):
        state = state_with(
            {"E4": [pc(P.WHITE, T.REINFORCEMENT), pc(P.WHITE, T.INFANTRY)]}
        )
        moves = set(legal_actions(state))
        self.assertIn(MoveAction(sq("E4"), sq("E5")), moves)
        self.assertIn(MoveAction(sq("E4"), sq("E6")), moves)
        self.assertNotIn(MoveAction(sq("E4"), sq("E4")), moves)
        blocked = state_with(
            {
                "E4": [pc(P.WHITE, T.REINFORCEMENT), pc(P.WHITE, T.INFANTRY)],
                "E5": [pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.INFANTRY)],
            }
        )
        self.assertFalse([a for a in legal_actions(blocked) if isinstance(a, MoveAction)])

    def test_black_infantry_moves_toward_rank_one(self):
        state = state_with({"E6": [pc(P.BLACK, T.INFANTRY)]}, turn=P.BLACK)
        self.assertIn(MoveAction(sq("E6"), sq("E5")), legal_actions(state))

    def test_sliding_piece_stops_at_first_occupied_square(self):
        state = state_with(
            {
                "A1": [pc(P.WHITE, T.CHARIOT)],
                "A2": [pc(P.WHITE, T.INFANTRY)],
                "A3": [pc(P.BLACK, T.INFANTRY)],
            }
        )
        moves = set(legal_actions(state))
        self.assertNotIn(MoveAction(sq("A1"), sq("A2")), moves)
        self.assertNotIn(MoveAction(sq("A1"), sq("A3")), moves)

    def test_capture_requires_equal_or_greater_height(self):
        state = state_with(
            {
                "A1": [pc(P.WHITE, T.MARSHAL)],
                "A2": [pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.CHARIOT)],
            }
        )
        self.assertNotIn(MoveAction(sq("A1"), sq("A2")), legal_actions(state))

    def test_shorter_move_attack_uses_mutual_bottom_attrition(self):
        state = state_with(
            {
                "A1": [pc(P.WHITE, T.INFANTRY)],
                "A2": [
                    pc(P.BLACK, T.REINFORCEMENT),
                    pc(P.BLACK, T.INFANTRY),
                    pc(P.BLACK, T.MARSHAL),
                ],
            },
            rules=ATTRITION_CONTROL_RULES,
        )
        action = MoveAction(sq("A1"), sq("A2"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertNotIn(sq("A1"), result.board)
        self.assertEqual(
            result.board[sq("A2")],
            (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)),
        )
        self.assertEqual(result.discards[P.WHITE][T.INFANTRY], 1)
        self.assertEqual(result.discards[P.BLACK][T.REINFORCEMENT], 1)

    def test_equal_height_move_still_captures_and_occupies(self):
        state = state_with(
            {
                "A1": [pc(P.WHITE, T.REINFORCEMENT), pc(P.WHITE, T.INFANTRY)],
                "A2": [pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)],
            },
            rules=ATTRITION_CONTROL_RULES,
        )
        result = apply_action(state, MoveAction(sq("A1"), sq("A2")))
        self.assertEqual(
            result.board[sq("A2")],
            (pc(P.WHITE, T.REINFORCEMENT), pc(P.WHITE, T.INFANTRY)),
        )
        self.assertEqual(sum(result.discards[P.WHITE].values()), 0)
        self.assertEqual(sum(result.discards[P.BLACK].values()), 2)

    def test_griffin_height_three_uses_short_and_long_leaps(self):
        state = state_with(
            {
                "E5": [pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.CHARIOT), pc(P.WHITE, T.GRIFFIN)],
                "E6": [pc(P.BLACK, T.INFANTRY)],
            }
        )
        moves = set(legal_actions(state))
        self.assertIn(MoveAction(sq("E5"), sq("H7")), moves)
        self.assertIn(MoveAction(sq("E5"), sq("G8")), moves)
        self.assertIn(MoveAction(sq("E5"), sq("F7")), moves)
        self.assertIn(MoveAction(sq("E5"), sq("G6")), moves)
        self.assertNotIn(MoveAction(sq("E5"), sq("H9")), moves)

    def test_griffin_height_one_and_two_use_chess_chariot_leaps(self):
        for stack in (
            [pc(P.WHITE, T.GRIFFIN)],
            [pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.GRIFFIN)],
        ):
            state = state_with({"E5": stack})
            moves = set(legal_actions(state))
            self.assertIn(MoveAction(sq("E5"), sq("F7")), moves)
            self.assertIn(MoveAction(sq("E5"), sq("G6")), moves)
            self.assertNotIn(MoveAction(sq("E5"), sq("H7")), moves)


class PlacementTests(unittest.TestCase):
    def test_open_placement_territory_and_friendly_stacking(self):
        reserves = {P.WHITE: Counter({T.MARSHAL: 1}), P.BLACK: Counter()}
        state = state_with({"A9": [pc(P.WHITE, T.INFANTRY)]}, reserves=reserves)
        actions = set(legal_actions(state))
        self.assertIn(PlaceAction(T.MARSHAL, sq("A4")), actions)
        self.assertNotIn(PlaceAction(T.MARSHAL, sq("B7")), actions)
        self.assertIn(PlaceAction(T.MARSHAL, sq("A9")), actions)

    def test_sovereign_cannot_be_stacked_or_field_promoted(self):
        reserves = {
            P.WHITE: Counter({T.INFANTRY: 1, T.REINFORCEMENT: 1}),
            P.BLACK: Counter(),
        }
        state = state_with({"E1": [pc(P.WHITE, T.SOVEREIGN)]}, reserves=reserves)
        actions = set(legal_actions(state))
        self.assertNotIn(PlaceAction(T.INFANTRY, sq("E1")), actions)
        self.assertNotIn(PlaceAction(T.REINFORCEMENT, sq("E1")), actions)

    def test_reinforcement_goes_under_stack(self):
        reserves = {P.WHITE: Counter({T.REINFORCEMENT: 1}), P.BLACK: Counter()}
        state = state_with({"A4": [pc(P.WHITE, T.MARSHAL)]}, reserves=reserves)
        result = apply_action(state, PlaceAction(T.REINFORCEMENT, sq("A4")))
        self.assertEqual(
            result.board[sq("A4")],
            (pc(P.WHITE, T.REINFORCEMENT), pc(P.WHITE, T.MARSHAL)),
        )


class SpecialPieceTests(unittest.TestCase):
    def test_ballista_generates_no_fire_and_only_visible_legal_targets(self):
        reserves = {P.WHITE: Counter({T.BALLISTA: 1}), P.BLACK: Counter()}
        state = state_with(
            {
                "E6": [pc(P.BLACK, T.INFANTRY)],
                "F4": [pc(P.BLACK, T.INFANTRY)],
                "H4": [pc(P.BLACK, T.INFANTRY)],  # blocked by F4
                "D4": [pc(P.BLACK, T.SOVEREIGN)],
            },
            reserves=reserves,
        )
        actions = set(legal_actions(state))
        self.assertIn(PlaceAction(T.BALLISTA, sq("E4")), actions)
        self.assertIn(PlaceAction(T.BALLISTA, sq("E4"), sq("E6")), actions)
        self.assertIn(PlaceAction(T.BALLISTA, sq("E4"), sq("F4")), actions)
        self.assertNotIn(PlaceAction(T.BALLISTA, sq("E4"), sq("H4")), actions)
        self.assertNotIn(PlaceAction(T.BALLISTA, sq("E4"), sq("D4")), actions)

    def test_shorter_artillery_only_attrits_target_bottom(self):
        reserves = {P.WHITE: Counter({T.BALLISTA: 1}), P.BLACK: Counter()}
        state = state_with(
            {
                "E6": [
                    pc(P.BLACK, T.REINFORCEMENT),
                    pc(P.BLACK, T.INFANTRY),
                    pc(P.BLACK, T.MARSHAL),
                ]
            },
            reserves=reserves,
            rules=ATTRITION_CONTROL_RULES,
        )
        action = PlaceAction(T.BALLISTA, sq("E4"), sq("E6"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertEqual(result.board[sq("E4")], (pc(P.WHITE, T.BALLISTA),))
        self.assertEqual(
            result.board[sq("E6")],
            (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)),
        )
        self.assertEqual(result.discards[P.WHITE][T.BALLISTA], 0)
        self.assertEqual(result.discards[P.BLACK][T.REINFORCEMENT], 1)

    def test_trebuchet_uses_forward_diagonals(self):
        reserves = {P.WHITE: Counter({T.TREBUCHET: 1}), P.BLACK: Counter()}
        state = state_with(
            {"G6": [pc(P.BLACK, T.INFANTRY)], "G2": [pc(P.BLACK, T.INFANTRY)]},
            reserves=reserves,
        )
        actions = set(legal_actions(state))
        self.assertIn(PlaceAction(T.TREBUCHET, sq("E4"), sq("G6")), actions)
        self.assertNotIn(PlaceAction(T.TREBUCHET, sq("E4"), sq("G2")), actions)

    def test_spy_preserves_order_and_consumes_replacements(self):
        reserves = {
            P.WHITE: Counter({T.SPY: 1, T.REINFORCEMENT: 1, T.MARSHAL: 1}),
            P.BLACK: Counter(),
        }
        state = state_with(
            {"E5": [pc(P.BLACK, T.REINFORCEMENT), pc(P.BLACK, T.MARSHAL)]},
            reserves=reserves,
        )
        action = PlaceAction(T.SPY, sq("E5"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertEqual(
            result.board[sq("E5")],
            (
                pc(P.WHITE, T.REINFORCEMENT),
                pc(P.WHITE, T.MARSHAL),
                pc(P.WHITE, T.SPY),
            ),
        )
        self.assertEqual(result.discards[P.BLACK][T.REINFORCEMENT], 1)
        self.assertEqual(result.discards[P.BLACK][T.MARSHAL], 1)
        self.assertEqual(result.reserves[P.WHITE][T.MARSHAL], 0)

    def test_placed_spy_cannot_also_supply_enemy_spy_replacement(self):
        reserves = {P.WHITE: Counter({T.SPY: 1}), P.BLACK: Counter()}
        state = state_with({"E5": [pc(P.BLACK, T.SPY)]}, reserves=reserves)
        self.assertNotIn(PlaceAction(T.SPY, sq("E5")), legal_actions(state))

        state.reserves[P.WHITE][T.SPY] = 2
        self.assertIn(PlaceAction(T.SPY, sq("E5")), legal_actions(state))

    def test_recalled_spy_does_not_consume_extra_spy_from_reserve(self):
        reserves = {
            P.WHITE: Counter({T.RECALL: 1, T.SPY: 1}),
            P.BLACK: Counter(),
        }
        discards = {P.WHITE: Counter({T.SPY: 1}), P.BLACK: Counter()}
        state = state_with(
            {"E5": [pc(P.BLACK, T.SPY)]}, reserves=reserves, discards=discards
        )
        action = RecallAction(T.SPY, sq("E5"))
        self.assertIn(action, legal_actions(state))
        result = apply_action(state, action)
        self.assertEqual(result.reserves[P.WHITE][T.SPY], 0)
        self.assertEqual(result.board[sq("E5")][-1], pc(P.WHITE, T.SPY))

    def test_recall_reinforcement_but_never_sovereign(self):
        reserves = {P.WHITE: Counter({T.RECALL: 1}), P.BLACK: Counter()}
        discards = {
            P.WHITE: Counter({T.REINFORCEMENT: 1, T.SOVEREIGN: 1}),
            P.BLACK: Counter(),
        }
        state = state_with(
            {"A4": [pc(P.WHITE, T.MARSHAL)]}, reserves=reserves, discards=discards
        )
        actions = set(legal_actions(state))
        fp_action = RecallAction(T.REINFORCEMENT, sq("A4"))
        self.assertIn(fp_action, actions)
        self.assertFalse(
            [a for a in actions if isinstance(a, RecallAction) and a.piece is T.SOVEREIGN]
        )
        result = apply_action(state, fp_action)
        self.assertEqual(result.reserves[P.WHITE][T.RECALL], 0)
        self.assertEqual(result.discards[P.WHITE][T.RECALL], 1)
        self.assertEqual(result.discards[P.WHITE][T.REINFORCEMENT], 0)


class TerminalAndInvariantTests(unittest.TestCase):
    def test_capturing_sovereign_ends_game_immediately(self):
        state = state_with(
            {"E8": [pc(P.WHITE, T.MARSHAL)], "E9": [pc(P.BLACK, T.SOVEREIGN)]}
        )
        result = apply_action(state, MoveAction(sq("E8"), sq("E9")))
        self.assertEqual(result.winner, P.WHITE)
        self.assertTrue(result.is_over)
        self.assertEqual(legal_actions(result), [])

    def test_next_player_with_no_legal_action_causes_draw(self):
        state = state_with(
            {
                "A1": [pc(P.WHITE, T.INFANTRY)],
                "A9": [pc(P.BLACK, T.SOVEREIGN)],
                "A8": [pc(P.BLACK, T.SPY)],
                "B8": [pc(P.BLACK, T.SPY)],
                "B9": [pc(P.BLACK, T.SPY)],
            }
        )
        result = apply_action(state, MoveAction(sq("A1"), sq("A2")))
        self.assertTrue(result.is_draw)
        self.assertIsNone(result.winner)
        self.assertEqual(legal_actions(result), [])

    def test_random_legal_play_preserves_invariants(self):
        rng = random.Random(20261001)
        state = initial_state()
        for _ in range(120):
            if state.is_over:
                break
            actions = legal_actions(state)
            self.assertTrue(actions)
            state = apply_action(state, rng.choice(actions))
            validate_state(state, enforce_inventory=True)

    def test_random_attrition_play_preserves_invariants(self):
        rng = random.Random(20261003)
        state = initial_state(ATTRITION_CONTROL_RULES)
        for _ in range(160):
            if state.is_over:
                break
            actions = legal_actions(state)
            self.assertTrue(actions)
            state = apply_action(state, rng.choice(actions))
            validate_state(state, enforce_inventory=True)


if __name__ == "__main__":
    unittest.main()
