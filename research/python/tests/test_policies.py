import random
import unittest
from collections import Counter, defaultdict

from stack_chess import (
    GameState,
    MoveAction,
    Piece,
    PieceType as T,
    PlaceAction,
    Player as P,
    apply_action,
    is_sovereign_threatened,
    legal_actions,
    parse_square as sq,
    preview_action,
    ruleset_by_id,
)
from stack_chess.policies import (
    ArtilleryReserveV2Policy,
    ArtilleryRushPolicy,
    ArtilleryBatteryPolicy,
    BalancedV2Policy,
    EvasionPolicy,
    HeightV2Policy,
    HeightRushPolicy,
    HeightInterceptorPolicy,
    HeuristicPolicy,
    HybridHeightPolicy,
    MaterialV2Policy,
    SovereignRacePolicy,
    SovereignDefensePolicy,
    SovereignPressureV2Policy,
    SpyV2Policy,
    TacticalSearchPolicy,
    ThreatDevelopmentPolicy,
    MaterialControlPolicy,
    NeutralDenialPolicy,
    OPENING_PLANS,
    ReserveHoarderPolicy,
    SpyRushPolicy,
    _vector_piece_weight,
    action_purpose_count,
    is_free_capture,
    opening_target_profile,
    policy_by_name,
    is_royal_interposition_trap,
    sovereign_attack_profile,
    valuable_burial_value,
)
from tournament import (
    DECISION_REASONS,
    _capture_quality,
    _capture_quality_declined,
    _griffin_jump,
    play_game,
)


def pc(owner, kind):
    return Piece(owner, kind)


class PolicyTests(unittest.TestCase):
    def test_tactical_search_wraps_existing_policy_without_replacing_identity(self):
        policy = policy_by_name("balanced_v2", tactical_search=True)
        self.assertIsInstance(policy, TacticalSearchPolicy)
        self.assertIsInstance(policy.base, BalancedV2Policy)
        self.assertEqual(policy.name, "balanced_v2")

    def test_tactical_search_rejects_stack_donation_to_royal_attack(self):
        bad = MoveAction(sq("E2"), sq("E4"))

        class FixedPolicy:
            name = "fixed"

            def choose(self, state, actions, rng):
                del state, rng
                return bad if bad in actions else actions[0]

        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E2"): (pc(P.WHITE, T.MARSHAL),),
                sq("F5"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertIn(bad, legal_actions(state))
        policy = TacticalSearchPolicy(base=FixedPolicy())
        chosen = policy.choose(state, legal_actions(state), random.Random(70))
        self.assertNotEqual(chosen, bad)
        self.assertTrue(policy.last_search_info["searched"])
        self.assertTrue(policy.last_search_info["overrode"])

    def test_artillery_shot_is_not_universally_treated_as_free_capture(self):
        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E6"): (pc(P.BLACK, T.INFANTRY),),
                sq("I9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.BALLISTA: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        shot = PlaceAction(T.BALLISTA, sq("E4"), sq("E6"))
        self.assertIn(shot, legal_actions(state))
        self.assertFalse(is_free_capture(state, shot))

    def test_competent_policy_takes_sovereign_capture_over_infiltration(self):
        state = GameState(
            board={
                sq("A8"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E8"): (pc(P.WHITE, T.CHARIOT),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
            rules=ruleset_by_id("development-infiltration-v1"),
            development_placements={P.WHITE: 4, P.BLACK: 4},
        )
        choices = legal_actions(state)
        self.assertIn(MoveAction(sq("A8"), sq("A9")), choices)
        self.assertIn(MoveAction(sq("E8"), sq("E9")), choices)
        action = BalancedV2Policy().choose(state, choices, random.Random(9))
        self.assertEqual(action, MoveAction(sq("E8"), sq("E9")))

    def test_competent_policy_prioritizes_free_capture(self):
        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.INFANTRY),),
                sq("D5"): (pc(P.BLACK, T.INFANTRY),),
                sq("I9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        capture = MoveAction(sq("D4"), sq("D5"))
        self.assertTrue(is_free_capture(state, capture))
        action = BalancedV2Policy().choose(state, legal_actions(state), random.Random(10))
        self.assertEqual(action, capture)

    def test_capture_quality_identifies_free_capture(self):
        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("D4"): (pc(P.WHITE, T.INFANTRY),),
                sq("D5"): (pc(P.BLACK, T.INFANTRY),),
                sq("I9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = MoveAction(sq("D4"), sq("D5"))
        self.assertIn(action, legal_actions(state))
        quality = _capture_quality(state, action)
        self.assertTrue(quality["sovereign_safe"])
        self.assertTrue(quality["favorable"])
        self.assertTrue(quality["secure"])
        self.assertTrue(quality["free"])

    def test_free_capture_is_not_declined_when_another_capture_is_chosen(self):
        self.assertFalse(
            _capture_quality_declined(
                "free",
                available=True,
                capture_chosen=True,
                chosen_quality={"free": False},
            )
        )
        self.assertTrue(
            _capture_quality_declined(
                "free",
                available=True,
                capture_chosen=False,
                chosen_quality={},
            )
        )

    def test_competent_policy_overlays_are_registered(self):
        expected = {
            "balanced_v2": BalancedV2Policy,
            "height_v2": HeightV2Policy,
            "spy_v2": SpyV2Policy,
            "material_v2": MaterialV2Policy,
            "sovereign_pressure_v2": SovereignPressureV2Policy,
            "artillery_reserve_v2": ArtilleryReserveV2Policy,
        }
        for name, policy_type in expected.items():
            self.assertIsInstance(policy_by_name(name), policy_type)

    def test_vector_piece_weight_matches_sovereign_geometry(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertGreater(
            _vector_piece_weight(state, T.CHARIOT, sq("E3")),
            _vector_piece_weight(state, T.DRAGOON, sq("E3")),
        )
        self.assertGreater(
            _vector_piece_weight(state, T.DRAGOON, sq("A5")),
            _vector_piece_weight(state, T.CHARIOT, sq("A5")),
        )

    def test_action_purpose_counts_capture_and_sovereign_threat(self):
        state = GameState(
            board={
                sq("A1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E4"): (pc(P.WHITE, T.CHARIOT),),
                sq("E7"): (pc(P.BLACK, T.INFANTRY),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        action = MoveAction(sq("E4"), sq("E7"))
        result = preview_action(state, action)
        self.assertGreaterEqual(action_purpose_count(state, action, result), 2)

    def test_threat_development_recognizes_protected_converging_attack(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E3"): (pc(P.WHITE, T.CHARIOT),),
                sq("E6"): (pc(P.WHITE, T.CHARIOT),),
                sq("H9"): (pc(P.WHITE, T.CHARIOT),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter(), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertEqual(sovereign_attack_profile(state, P.WHITE), (2, 1))

    def test_threat_development_identifies_safe_royal_interposition_trap(self):
        rules = ruleset_by_id("attrition-neutral-gate-opening-4-v1")
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("E4"): (pc(P.BLACK, T.INFANTRY), pc(P.BLACK, T.CHARIOT)),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
            rules=rules,
            development_placements={P.WHITE: 4, P.BLACK: 4},
            height_three_unlocked={P.WHITE: False, P.BLACK: False},
        )
        action = PlaceAction(T.INFANTRY, sq("E2"))
        self.assertIn(action, legal_actions(state))
        self.assertTrue(is_royal_interposition_trap(state, action))

    def test_threat_development_penalizes_burying_premium_material(self):
        state = GameState(
            board={
                sq("E1"): (pc(P.WHITE, T.SOVEREIGN),),
                sq("B2"): (pc(P.WHITE, T.DRAGOON),),
                sq("E9"): (pc(P.BLACK, T.SOVEREIGN),),
            },
            reserves={P.WHITE: Counter({T.INFANTRY: 1}), P.BLACK: Counter()},
            discards={P.WHITE: Counter(), P.BLACK: Counter()},
        )
        self.assertEqual(
            valuable_burial_value(state, PlaceAction(T.INFANTRY, sq("B2"))),
            3.0,
        )
        self.assertIsInstance(policy_by_name("threat_development"), ThreatDevelopmentPolicy)

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
            first_move_piece_total = sum(
                stats[f"first_move_piece_{kind.value}"] for kind in T
            )
            self.assertEqual(
                first_move_piece_total,
                stats["games_with_first_any_move"],
            )
            self.assertEqual(
                stats["games_with_first_neutral_move"]
                + stats["player_games_without_neutral_move"],
                stats["player_games"],
            )
            self.assertLessEqual(
                stats["player_games_with_h3_before_neutral_move"],
                stats["player_games"],
            )

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

    def test_complete_game_can_be_captured_as_replay(self):
        telemetry = defaultdict(Counter)
        replays = []
        result = play_game(
            "tactical",
            "height_rush@griffin",
            202,
            500,
            telemetry,
            ruleset_id="attrition-neutral-gate-opening-4-v1",
            replays=replays,
        )
        self.assertEqual(len(replays), 1)
        self.assertEqual(len(replays[0]["actions"]), result.plies)
        self.assertEqual(replays[0]["metadata"]["plies"], result.plies)
        self.assertEqual(replays[0]["metadata"]["win_reason"], result.win_reason)


if __name__ == "__main__":
    unittest.main()
