import random
import unittest
from collections import Counter, defaultdict

from stack_chess import (
    GameState,
    MoveAction,
    Piece,
    PieceType as T,
    Player as P,
    apply_action,
    is_sovereign_threatened,
    legal_actions,
    parse_square as sq,
    preview_action,
    ruleset_by_id,
)
from stack_chess.policies import (
    ArtilleryRushPolicy,
    ArtilleryBatteryPolicy,
    EvasionPolicy,
    HeightRushPolicy,
    HeightInterceptorPolicy,
    HeuristicPolicy,
    HybridHeightPolicy,
    SovereignRacePolicy,
    SovereignDefensePolicy,
    MaterialControlPolicy,
    NeutralDenialPolicy,
    OPENING_PLANS,
    ReserveHoarderPolicy,
    SpyRushPolicy,
    opening_target_profile,
    policy_by_name,
)
from tournament import DECISION_REASONS, _griffin_jump, play_game


def pc(owner, kind):
    return Piece(owner, kind)


class PolicyTests(unittest.TestCase):
    def test_heuristic_immediately_takes_infiltration_win(self):
        state = GameState(
            board={
                sq("E8"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E1"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
            rules=ruleset_by_id("development-infiltration-v1"),
            development_placements={P.WHITE: 4, P.BLACK: 4},
        )
        action = HeuristicPolicy().choose(
            state, legal_actions(state), random.Random(3)
        )
        self.assertIsInstance(action, MoveAction)
        self.assertEqual(action.destination[1], 8)

    def test_sovereign_defense_removes_current_launching_stack(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("C3"): (pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.CHARIOT)),
                sq("E3"): (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertTrue(is_sovereign_threatened(state, P.WHITE))
        action = SovereignDefensePolicy().choose(
            state, legal_actions(state), random.Random(43)
        )
        self.assertEqual(action, MoveAction(sq("C3"), sq("E3")))

    def test_every_screened_policy_has_three_opening_plans(self):
        for name in (
            "tactical",
            "material_control",
            "spy_rush",
            "artillery_rush",
            "height_rush",
            "sovereign_race",
        ):
            self.assertEqual(len(OPENING_PLANS[name]), 3)
            for plan_name in OPENING_PLANS[name]:
                self.assertEqual(sum(opening_target_profile(name, plan_name)), 4)

        self.assertEqual(
            opening_target_profile("sovereign_defense", "intercept"), (1, 1, 2)
        )

    def test_planned_policy_hands_control_to_base_after_development(self):
        policy = policy_by_name("height_rush@split")
        self.assertEqual(policy.name, "height_rush@split")
        self.assertEqual(policy.base.name, "height_rush")

    def test_material_control_takes_favorable_capture(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.INFANTRY),),
                sq("D5"): (pc(P.BLACK, T.MARSHAL),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = MaterialControlPolicy().choose(
            state, legal_actions(state), random.Random(41)
        )
        self.assertEqual(action, MoveAction(sq("D4"), sq("D5")))

    def test_preview_matches_normal_transition_for_non_draw_position(self):
        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.INFANTRY),),
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = MoveAction(sq("A1"), sq("A2"))
        preview = preview_action(state, action)
        applied = apply_action(state, action)
        self.assertEqual(preview.board, applied.board)
        self.assertEqual(preview.reserves, applied.reserves)
        self.assertEqual(preview.discards, applied.discards)
        self.assertEqual(preview.turn, applied.turn)
        self.assertEqual(preview.ply, applied.ply)

    def test_heuristic_always_takes_immediate_sovereign_capture(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E8"): (pc(P.WHITE, T.MARSHAL),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = HeuristicPolicy().choose(state, legal_actions(state), random.Random(7))
        self.assertEqual(action, MoveAction(sq("E8"), sq("E9")))

    def test_zero_blunder_policy_answers_immediate_sovereign_threat(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("A1"): (pc(P.WHITE, T.INFANTRY),),
                sq("E3"): (pc(P.BLACK, T.MARSHAL),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertTrue(is_sovereign_threatened(state, P.WHITE))
        policy = HeuristicPolicy(tactical_blunder_rate=0.0)
        action = policy.choose(state, legal_actions(state), random.Random(11))
        self.assertFalse(is_sovereign_threatened(preview_action(state, action), P.WHITE))

    def test_spy_rush_prioritizes_legal_conversion(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E8"): (pc(P.BLACK, T.INFANTRY),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.SPY: 1, T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = SpyRushPolicy().choose(state, legal_actions(state), random.Random(3))
        self.assertEqual(action.piece, T.SPY)
        self.assertEqual(action.destination, sq("E8"))

    def test_heuristic_avoids_nonconverting_spy_placement(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={
                P.WHITE: Counter({T.SPY: 1, T.INFANTRY: 1}),
                P.BLACK: Counter(),
            },
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        actions = legal_actions(state)
        policy = HeuristicPolicy()
        for seed in range(100):
            action = policy.choose(state, actions, random.Random(seed))
            self.assertFalse(
                not isinstance(action, MoveAction) and action.piece is T.SPY
            )

    def test_neutral_denial_does_not_open_with_spy(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={
                P.WHITE: Counter({T.SPY: 1, T.INFANTRY: 1}),
                P.BLACK: Counter(),
            },
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = NeutralDenialPolicy().choose(
            state, legal_actions(state), random.Random(5)
        )
        self.assertEqual(action.piece, T.INFANTRY)

    def test_artillery_rush_prioritizes_immediate_shot(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E6"): (pc(P.BLACK, T.INFANTRY),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.BALLISTA: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = ArtilleryRushPolicy().choose(state, legal_actions(state), random.Random(5))
        self.assertEqual(action.piece, T.BALLISTA)
        self.assertIsNotNone(action.effect_target)

    def test_height_three_griffin_jump_classification(self):
        self.assertEqual(_griffin_jump(MoveAction(sq("A1"), sq("B3"))), "short")
        self.assertEqual(_griffin_jump(MoveAction(sq("A1"), sq("C4"))), "long")
        self.assertIsNone(_griffin_jump(MoveAction(sq("A1"), sq("D5"))))

    def test_neutral_denial_prioritizes_open_neutral_square(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = NeutralDenialPolicy().choose(
            state, legal_actions(state), random.Random(13)
        )
        self.assertFalse(isinstance(action, MoveAction))
        self.assertIn(action.destination[1], (3, 4, 5))
        self.assertNotIn(action.destination, state.board)

    def test_height_rush_prioritizes_mobile_height_three_stack(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.CHARIOT)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.MARSHAL: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = HeightRushPolicy().choose(state, legal_actions(state), random.Random(17))
        self.assertFalse(isinstance(action, MoveAction))
        self.assertEqual(action.destination, sq("D4"))
        self.assertEqual(action.piece, T.MARSHAL)

    def test_reserve_hoarder_preserves_last_protected_copy(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("A2"): (pc(P.WHITE, T.INFANTRY),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={
                P.WHITE: Counter({T.MARSHAL: 1, T.INFANTRY: 2}),
                P.BLACK: Counter(),
            },
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        policy = ReserveHoarderPolicy()
        preserving = [
            action
            for action in legal_actions(state)
            if policy._preserves_floor(state, action)
        ]
        self.assertFalse(
            [
                action
                for action in preserving
                if not isinstance(action, MoveAction) and action.piece is T.MARSHAL
            ]
        )

    def test_evasion_declines_available_non_sovereign_capture(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.MARSHAL),),
                sq("D5"): (pc(P.BLACK, T.INFANTRY),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = EvasionPolicy().choose(state, legal_actions(state), random.Random(19))
        self.assertIsInstance(action, MoveAction)
        self.assertNotIn(action.destination, state.board)

    def test_height_interceptor_holds_spy_for_height_two_target(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("A8"): (pc(P.BLACK, T.INFANTRY),),
                sq("D8"): (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={
                P.WHITE: Counter({T.SPY: 1, T.INFANTRY: 2, T.MARSHAL: 1}),
                P.BLACK: Counter(),
            },
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = HeightInterceptorPolicy().choose(
            state, legal_actions(state), random.Random(23)
        )
        self.assertFalse(isinstance(action, MoveAction))
        self.assertEqual(action.piece, T.SPY)
        self.assertEqual(action.destination, sq("D8"))

    def test_artillery_battery_uses_equal_height_shot(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E4"): (pc(P.WHITE, T.INFANTRY),),
                sq("E6"): (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.MARSHAL)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.BALLISTA: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = ArtilleryBatteryPolicy().choose(
            state, legal_actions(state), random.Random(29)
        )
        self.assertEqual(action.piece, T.BALLISTA)
        self.assertEqual(action.destination, sq("E4"))
        self.assertEqual(action.effect_target, sq("E6"))

    def test_hybrid_height_builds_up_to_target(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.INFANTRY), pc(P.WHITE, T.CHARIOT)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.GRIFFIN: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = HybridHeightPolicy().choose(
            state, legal_actions(state), random.Random(31)
        )
        self.assertFalse(isinstance(action, MoveAction))
        self.assertEqual(action.destination, sq("D4"))

    def test_sovereign_race_prioritizes_new_sovereign_threat(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("B8"): (pc(P.WHITE, T.CHARIOT),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = SovereignRacePolicy().choose(state, legal_actions(state), random.Random(37))
        self.assertTrue(
            is_sovereign_threatened(preview_action(state, action), P.BLACK)
        )

    def test_tournament_decisions_and_final_material_are_conserved(self):
        telemetry = defaultdict(Counter)
        play_game("height_rush", "sovereign_race", 101, 200, telemetry)
        for name in ("height_rush", "sovereign_race"):
            stats = telemetry[name]
            self.assertEqual(
                stats["actions"],
                sum(stats[f"decision_{reason}"] for reason in DECISION_REASONS),
            )
            final_material = sum(
                stats[f"final_reserve_{kind.value}_total"]
                + stats[f"final_board_{kind.value}_total"]
                + stats[f"final_discard_{kind.value}_total"]
                for kind in T
            )
            self.assertEqual(final_material, 27 * stats["player_games"])

    def test_ply_limit_captures_replay_and_endgame_diagnostics(self):
        telemetry = defaultdict(Counter)
        replays = []
        result = play_game(
            "tactical",
            "sovereign_race@dual",
            101,
            1,
            telemetry,
            opening="development",
            ruleset_id="development-v3",
            limit_replays=replays,
        )
        self.assertTrue(result.hit_limit)
        self.assertIsNotNone(result.limit_diagnostics)
        self.assertEqual(len(replays), 1)
        self.assertEqual(len(replays[0]["actions"]), 1)
        self.assertEqual(replays[0]["metadata"]["diagnostics"], result.limit_diagnostics)
        self.assertTrue(all(result.limit_diagnostics["sovereigns_present"].values()))


if __name__ == "__main__":
    unittest.main()
