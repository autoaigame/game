# A zombie made from scratch: mesh, skeleton, weights and animations all built here, with the helpers of
# art/models/rig_kit.py. No imported model, skeleton or animation.
#
#   blender -b --python art/models/zombie.py -- <repo root>
#
# Writes assets/models/zombie.glb (skeleton, one mesh with one material per colour, clips idle, walk,
# attack, death) and assets/models/zombie_clips.json (what client/zombie_3d.gd reads, and the checks).
#
# - Shape: simple volumes readable at about 100 px: a hunched body (the hunch is in the poses, the rest
#   pose stands straight), arms held forward, a big head with dark sockets and pale eyes, a torn shirt
#   (jagged hem over a bare belly, one sleeve torn short), trousers torn above one knee, one bare foot.
# - Skeleton: the player's bone names for the bones they share (DEF-hips, DEF-spine.001 ... DEF-head,
#   DEF-thigh.L ...), so code that looks bones up by name (the head lift of client/character_3d.gd)
#   finds them. The orientations and lengths are this model's own: the player's clips do not fit it.
# - Colours: flat colours of data/palette.json (the renderer snaps the light to palette colours of the
#   same hue): olive greens for the skin, grey shirt, brown trousers, brick stains.
# - Animations: functions of time, sampled on every frame (rig_kit.bake). Legs by two-bone IK on foot
#   paths; spine, head and arms by rotations from sine waves with phase lags and eased key curves.
import math, os, sys
from mathutils import Vector, Quaternion

sys.dont_write_bytecode = True  # no __pycache__ in the repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_kit as K

ROOT = sys.argv[sys.argv.index("--") + 1]
OUT = os.path.join(ROOT, "assets/models")

PALETTE = {"skin": "767d52", "skin_dark": "616a43", "shirt": "77756c", "stain": "7a3f36", "trousers": "54483a",
        "shoe": "3a2f27", "socket": "2e2822", "eye": "d3ccb7", "hair": "40372d"}

# Skeleton: (bone, parent, head, tail), metres, facing -Y. Mirrored for .R.
HIPS_Z = 0.90
BONES = [
    ("root", None, (0, 0, 0), (0, 0, 0.15)),
    ("DEF-hips", "root", (0, 0, HIPS_Z), (0, 0, 1.02)),
    ("DEF-spine.001", "DEF-hips", (0, 0, 1.02), (0, 0, 1.14)),
    ("DEF-spine.002", "DEF-spine.001", (0, 0, 1.14), (0, 0, 1.26)),
    ("DEF-spine.003", "DEF-spine.002", (0, 0, 1.26), (0, 0, 1.40)),
    ("DEF-neck", "DEF-spine.003", (0, -0.01, 1.40), (0, -0.02, 1.47)),
    ("DEF-head", "DEF-neck", (0, -0.02, 1.47), (0, -0.02, 1.74)),
]
for s, x in (("L", 1), ("R", -1)):
    BONES += [
        ("DEF-shoulder." + s, "DEF-spine.003", (0.04 * x, 0, 1.37), (0.26 * x, 0, 1.37)),
        ("DEF-upper_arm." + s, "DEF-shoulder." + s, (0.26 * x, 0, 1.37), (0.28 * x, 0, 1.09)),
        ("DEF-forearm." + s, "DEF-upper_arm." + s, (0.28 * x, 0, 1.09), (0.29 * x, 0, 0.84)),
        ("DEF-hand." + s, "DEF-forearm." + s, (0.29 * x, 0, 0.84), (0.29 * x, 0, 0.70)),
        ("DEF-thigh." + s, "DEF-hips", (0.10 * x, 0, HIPS_Z), (0.11 * x, 0, 0.49)),
        ("DEF-shin." + s, "DEF-thigh." + s, (0.11 * x, 0, 0.49), (0.11 * x, 0, 0.09)),
        ("DEF-foot." + s, "DEF-shin." + s, (0.11 * x, 0, 0.09), (0.11 * x, -0.15, 0.04)),
    ]
ANKLE_Z = 0.09


def jag(depth, teeth, seed=0):
    """A torn hem: the end ring's vertices alternately pulled back by `depth` (metres), unevenly."""
    def hem(i, n, end):
        k = (i * 7 + seed * 3) % 5
        tooth = (i % teeth == 0)
        return (-1 if end == 1 else 1) * depth * (1.0 if tooth else 0.35 + 0.1 * k)
    return hem


# Thickness of the volumes per bone (width and depth of their tubes): the player's body is stocky, and a
# thin limb is one or two pixels wide at game size.
GIRTH = {"DEF-spine": 1.2, "DEF-hips": 1.2, "DEF-neck": 1.3, "DEF-shoulder": 1.25, "DEF-upper_arm": 1.4,
        "DEF-forearm": 1.45, "DEF-hand": 1.3, "DEF-thigh": 1.3, "DEF-shin": 1.35, "DEF-foot": 1.2}


def model():
    b = K.Builder()
    b.girth = GIRTH
    front = -0.105 * GIRTH["DEF-spine"]  # the shirt's front, for the stains
    T = b.tube
    # Head: a big rounded block, jaw narrower, with the face on its front (-Y).
    T((0, -0.03, 1.46), (0, -0.03, 1.75), [(0, 0.15, 0.16), (0.3, 0.22, 0.22), (0.65, 0.25, 0.25), (1, 0.21, 0.21)],
            "DEF-head", "skin", square=0.6)
    for x in (1, -1):
        b.box((0.055 * x, -0.15, 1.615), (0.07, 0.03, 0.05), "DEF-head", "socket")
        b.box((0.05 * x, -0.165, 1.615), (0.03, 0.02, 0.025), "DEF-head", "eye")
        b.box((0.085 * x, -0.03, 1.73), (0.06, 0.12, 0.04), "DEF-head", "hair")
    b.box((0.0, -0.13, 1.515), (0.10, 0.04, 0.04), "DEF-head", "socket")  # gaping mouth
    b.box((0.0, -0.13, 1.67), (0.20, 0.03, 0.025), "DEF-head", "skin_dark")  # heavy brow
    T((0, -0.015, 1.38), (0, -0.02, 1.50), [(0, 0.11, 0.10), (1, 0.10, 0.10)], "DEF-neck", "skin")
    # Torso: skin, then the shirt over it, torn above a bare belly. The skin under the shirt is thinner
    # than the shirt by a margin, so it does not poke through when the back bends.
    T((0, 0, 0.98), (0, 0, 1.16), [(0, 0.27, 0.18), (1, 0.29, 0.19)], "DEF-spine.001", "skin_dark", ring_gap=0.04)
    T((0, 0, 1.12), (0, 0, 1.28), [(0, 0.28, 0.18), (1, 0.30, 0.19)], "DEF-spine.002", "skin")
    T((0, 0, 1.25), (0, 0, 1.43), [(0, 0.30, 0.19), (0.7, 0.34, 0.19), (1, 0.26, 0.16)], "DEF-spine.003", "skin")
    T((0, 0, 1.07), (0, 0, 1.16), [(0, 0.31, 0.21), (1, 0.31, 0.21)], "DEF-spine.001", "shirt", n=12,
            hem=jag(0.05, 3), cap=(False, False))
    T((0, 0, 1.13), (0, 0, 1.29), [(0, 0.31, 0.21), (1, 0.34, 0.23)], "DEF-spine.002", "shirt", n=12)
    T((0, 0, 1.26), (0, 0, 1.445), [(0, 0.34, 0.23), (0.7, 0.385, 0.23), (1, 0.30, 0.19)], "DEF-spine.003", "shirt",
            n=12)
    b.box((0.06, front - 0.012, 1.22), (0.10, 0.012, 0.12), "DEF-spine.002", "stain")
    b.box((-0.09, front - 0.016, 1.33), (0.07, 0.012, 0.08), "DEF-spine.003", "stain")
    # Pelvis in the trousers.
    T((0, 0, 0.82), (0, 0, 1.04), [(0, 0.30, 0.20), (1, 0.30, 0.20)], "DEF-hips", "trousers", n=10,
            ring_gap=0.04)
    for s, x in (("L", 1), ("R", -1)):
        # Shoulder pad of the shirt, upper arm, a torn sleeve (short on the left, to the elbow on the right).
        T((0.06 * x, 0, 1.38), (0.26 * x, 0, 1.37), [(0, 0.13, 0.15), (1, 0.12, 0.13)], "DEF-shoulder." + s, "shirt")
        T((0.26 * x, 0, 1.39), (0.28 * x, 0, 1.08), [(0, 0.10, 0.10), (1, 0.08, 0.08)], "DEF-upper_arm." + s, "skin")
        sleeve = 0.45 if s == "L" else 0.97
        top, end = Vector((0.26 * x, 0, 1.40)), Vector((0.28 * x, 0, 1.09))
        T(top, top.lerp(end, sleeve), [(0, 0.125, 0.125), (1, 0.115, 0.115)], "DEF-upper_arm." + s, "shirt",
                hem=jag(0.035, 2, seed=1 + x), cap=(True, False))
        T((0.28 * x, 0, 1.10), (0.29 * x, 0, 0.83), [(0, 0.08, 0.08), (1, 0.065, 0.065)], "DEF-forearm." + s, "skin")
        # Hand: long, flat, fingers as one block a shade darker (claws).
        T((0.29 * x, 0, 0.85), (0.29 * x, 0, 0.75), [(0, 0.06, 0.08), (1, 0.05, 0.10)], "DEF-hand." + s, "skin",
                square=0.8)
        T((0.29 * x, 0, 0.755), (0.29 * x, -0.01, 0.67), [(0, 0.05, 0.095), (1, 0.03, 0.07)], "DEF-hand." + s,
                "skin_dark", square=0.8)
        # Legs: trousers on the thighs; the left leg down to the ankle, the right torn above the knee.
        T((0.11 * x, 0, 0.92), (0.11 * x, 0, 0.49), [(0, 0.13, 0.13), (0.25, 0.15, 0.16), (1, 0.12, 0.13)], "DEF-thigh." + s,
                "trousers", n=10, ring_gap=0.05, hem=jag(0.04, 2, seed=2) if s == "R" else None, cap=(True, s == "L"))
        if s == "L":
            T((0.11 * x, 0, 0.51), (0.11 * x, 0, 0.08), [(0, 0.12, 0.13), (1, 0.115, 0.12)], "DEF-shin." + s,
                    "trousers", n=10, hem=jag(0.035, 2, seed=3))
            # Worn shoe.
            T((0.11 * x, 0.05, 0.056), (0.11 * x, -0.20, 0.031), [(0, 0.10, 0.09), (0.7, 0.11, 0.08), (1, 0.09, 0.06)],
                    "DEF-foot." + s, "shoe", square=0.8)
        else:
            T((0.11 * x, 0, 0.51), (0.11 * x, 0, 0.08), [(0, 0.10, 0.11), (1, 0.07, 0.075)], "DEF-shin." + s, "skin")
            # Bare foot.
            T((0.11 * x, 0.04, 0.051), (0.11 * x, -0.19, 0.026), [(0, 0.08, 0.08), (0.7, 0.09, 0.06), (1, 0.08, 0.04)],
                    "DEF-foot." + s, "skin_dark", square=0.8)
    # Balls at the joints that bend far (rig_kit.Builder.ball): each turns on itself with the bone below
    # the joint and fills the notch the bend opens between the volumes on either side. The volumes on
    # either side end inside their joint's ball (a shoulder pad stops at the arm's pivot, a thigh starts
    # narrow at the hip and stops at the knee): an end that sticks out of the ball shows when it bends.
    b.ball((0, 0, 1.02), 0.11, "DEF-spine.001", "skin_dark")  # waist, over the bare belly
    for s, x in (("L", 1), ("R", -1)):
        b.ball((0.26 * x, 0, 1.37), 0.095, "DEF-upper_arm." + s, "shirt")  # shoulder
        b.ball((0.28 * x, 0, 1.09), 0.062, "DEF-forearm." + s, "skin")  # elbow
        b.ball((0.10 * x, 0, HIPS_Z), 0.095, "DEF-thigh." + s, "trousers")  # hip
        b.ball((0.11 * x, 0, 0.49), 0.085 if s == "L" else 0.07, "DEF-shin." + s, "trousers" if s == "L" else "skin")  # knee
    b.sit_on_ground("DEF-foot")
    return b


# ---- Poses ----
# Angles in degrees. Pitch +: the top of an upright bone goes forward (-Y), so a hanging bone's tip goes
# back; roll +: towards the model's left (+X); yaw +: the front turns towards the left. Arms: elev 0 hangs down, 90 points forward, 180 up; spread +
# opens outwards.

def rot(pitch=0.0, roll=0.0, yaw=0.0):
    return K.axis_angle((0, 0, 1), yaw) @ K.axis_angle((0, 1, 0), roll) @ K.axis_angle((1, 0, 0), pitch)


def upper_body(P, st, hunch, sway, head_pitch, head_roll, arms, frame=Quaternion()):
    """Spine, neck, head and arms. hunch: total forward bend of the spine (spread over its 3 bones);
    sway: sideways lean (roll) of the spine; arms: {side: (elev, spread, elbow, droop)}; frame: a world
    rotation the arm directions are given in (the body's facing or its fall)."""
    for b, share in (("DEF-spine.001", 0.3), ("DEF-spine.002", 0.35), ("DEF-spine.003", 0.35)):
        st["q"][b] = rot(pitch=hunch * share, roll=sway * share)
    st["q"]["DEF-neck"] = rot(pitch=head_pitch * 0.4)
    st["q"]["DEF-head"] = rot(pitch=head_pitch * 0.6, roll=head_roll)
    for s, x in (("L", 1), ("R", -1)):
        elev, spread, elbow, droop = arms[s]
        # A bone hanging down swings forward with a negative pitch (its tip goes -Y).
        d = rot(yaw=x * spread) @ (rot(pitch=-elev) @ Vector((0, 0, -1)))
        P.aim(st, "DEF-upper_arm." + s, frame @ d)
        st["q"]["DEF-forearm." + s] = rot(pitch=-elbow)
        st["q"]["DEF-hand." + s] = rot(pitch=droop)


def legs(P, st, feet):
    """feet: {side: (ankle position, foot rotation)}; knees bend forward. Returns the worst miss (m)."""
    miss = 0.0
    for s, (ankle, q) in feet.items():
        x = 1 if s == "L" else -1
        miss = max(miss, P.ik(st, "DEF-thigh." + s, "DEF-shin." + s, ankle, (0.15 * x, -1, 0)))
        P.set_world(st, "DEF-foot." + s, q)
    return miss


def flat(yaw=0.0, toes=0.0):
    """A foot's world rotation: turned out by yaw, toes down by `toes` (degrees)."""
    return rot(yaw=yaw) @ rot(pitch=toes)


FOOT_FRONT = 0.20  # ankle to the tip of the toes along the foot
STANCE_FEET = {"L": (Vector((0.12, -0.06, ANKLE_Z)), flat(8)), "R": (Vector((-0.14, 0.07, ANKLE_Z)), flat(-18))}


def idle_pose(P, t):
    """3 s loop: weight shifting, a slow breath, the head lolling behind the body, arms swaying like
    pendulums, and one twitch of the head."""
    st = P.new()
    w = K.wave
    twitch = math.exp(-((t - 0.62) / 0.025) ** 2)
    st["off"] = Vector((0.025 * w(t), 0.01 * w(t, 0.25), -0.05 + 0.008 * w(t, 0, 2)))
    st["q"]["DEF-hips"] = rot(roll=-2.5 * w(t), yaw=3 * w(t, 0.1))
    upper_body(P, st, hunch=42 + 3 * w(t, 0.1, 2), sway=4 * w(t, 0.12), head_pitch=-38 + 4 * w(t, 0.2, 2),
            head_roll=9 * w(t, 0.3) + 14 * twitch,
            arms={"L": (68 + 5 * w(t, 0.35), 8, 22 + 4 * w(t, 0.4), 35), "R": (80 + 5 * w(t, 0.42), 6, 18, 40)})
    legs(P, st, STANCE_FEET)
    return st


WALK = dict(frames=45, stride=0.62, stance=0.66, lift={"L": 0.07, "R": 0.018}, drag_toes={"L": 0.0, "R": 22.0},
        contact={"L": 0.0, "R": 0.5}, track={"L": 0.12, "R": -0.14}, centre=-0.03, out={"L": 6.0, "R": -18.0})


def walk_foot(s, t):
    """A foot's ankle and rotation at loop time t. Stance: planted, moving back with the ground at the
    walking speed. Swing: forward again, eased, lifted (the right foot barely: it drags, toes down)."""
    W = WALK
    beta, S = W["stance"], W["stride"]
    u = (t - W["contact"][s]) % 1.0
    reach = beta * S  # how far the foot travels back while planted
    x = W["track"][s]
    if u < beta:
        y = W["centre"] - reach / 2 + S * u
        return Vector((x, y, ANKLE_Z)), flat(W["out"][s])
    k = (u - beta) / (1 - beta)
    y = W["centre"] + reach / 2 - reach * (0.5 - 0.5 * math.cos(math.pi * k))
    toes = W["drag_toes"][s] * math.sin(math.pi * k) ** 0.5
    z = ANKLE_Z + W["lift"][s] * math.sin(math.pi * k) + FOOT_FRONT * math.sin(math.radians(toes)) * 0.9
    swing_out = (0.05 if s == "R" else 0.0) * math.sin(math.pi * k)  # the stiff leg swings round
    return Vector((x - swing_out, y, z)), flat(W["out"][s], toes)


def walk_planted(s, t):
    return (t - WALK["contact"][s]) % 1.0 < WALK["stance"]


def walk_pose(P, t):
    """Shuffling walk, 1.5 s per cycle: a limp on the right leg (short, dragged steps), the hips lowest
    as each foot lands and lurching over the planted foot, the torso and head following with a lag, the
    arms held forward bobbing at the step rate."""
    st = P.new()
    w = K.wave
    bad = 1.0 if walk_planted("R", t) else 0.0  # weight on the bad leg: the hips sag more
    bob = -0.022 * (0.5 + 0.5 * math.cos(2 * math.pi * 2 * t)) - 0.015 * bad * math.sin(math.pi * ((t - 0.5) % 1 / 0.66))
    st["off"] = Vector((0.04 * math.cos(2 * math.pi * (t - 0.33)), -0.015 * w(t, 0.1, 2), -0.055 + bob))
    st["q"]["DEF-hips"] = rot(roll=4 * math.cos(2 * math.pi * (t - 0.33)), yaw=-8 * math.cos(2 * math.pi * t))
    face = rot(yaw=-8 * math.cos(2 * math.pi * t) * 0.3)
    upper_body(P, st, hunch=40 + 4 * w(t, 0.12, 2), sway=-6 * math.cos(2 * math.pi * (t - 0.45)),
            head_pitch=-36 + 6 * w(t, 0.2, 2), head_roll=10 * math.cos(2 * math.pi * (t - 0.55)),
            arms={"L": (78 + 5 * w(t, 0.2, 2) + 6 * math.cos(2 * math.pi * (t - 0.5)), 4, 14 + 6 * w(t, 0.3, 2), 30),
                  "R": (88 + 5 * w(t, 0.25, 2) + 6 * math.cos(2 * math.pi * t), 2, 10, 34)}, frame=face)
    legs(P, st, {s: walk_foot(s, t) for s in "LR"})
    return st


ATTACK = dict(frames=36, hit=0.45)


def attack_pose(P, t):
    """1.2 s, once: rears up with the arms raised (anticipation), lunges and claws down at the hit, holds,
    then sinks back to the idle stance. Every value follows eased keys (rig_kit.keys) through the same
    times: rest, raised (0.3), hit (0.45), hold (0.6), back (1.0)."""
    st = P.new()
    ts = (0.0, 0.3, ATTACK["hit"], 0.6, 1.0)
    k = lambda *vals: K.keys(list(zip(ts, vals)), t)
    st["off"] = Vector((0.0, k(0.0, 0.06, -0.11, -0.10, 0.0), k(-0.05, -0.02, -0.09, -0.09, -0.05)))
    st["q"]["DEF-hips"] = rot(pitch=k(0, -6, 10, 10, 0))
    upper_body(P, st, hunch=k(42, 10, 62, 58, 42), sway=0.0, head_pitch=k(-38, -30, -20, -24, -38), head_roll=k(0, -6, 4, 4, 0),
            arms={"L": (k(68, 165, 80, 65, 68), k(8, 30, -4, -6, 8), k(22, 35, 5, 12, 22), k(35, 10, 20, 30, 35)),
                  "R": (k(80, 160, 85, 70, 80), k(6, 32, -6, -8, 6), k(18, 30, 5, 10, 18), k(40, 10, 20, 30, 40))})
    legs(P, st, STANCE_FEET)
    return st


DEATH = dict(frames=48, buckle=0.35, down=0.8, pivot=Vector((0, -0.12, 0)))


def death_pose(P, t, lift=0.0):
    """1.6 s, once: the knees give (feet planted, hips dropping), then the whole body topples forward
    around a point on the ground ahead of the feet and lands face down, arms thrown forward; a small
    rebound at the end. `lift` raises the body (the ground correction of make_death)."""
    D = DEATH
    tb = min(t, D["buckle"])
    k = lambda pts, x: K.keys(pts, x)
    st = P.new()
    sink = k([(0, 0.0), (D["buckle"], 1.0)], tb)
    st["off"] = Vector((0, 0.04 * sink, -0.05 - 0.30 * sink))
    st["q"]["DEF-hips"] = rot(pitch=8 * sink)
    upper_body(P, st, hunch=42 + 20 * sink, sway=6 * sink, head_pitch=-38 + 40 * sink, head_roll=10 * sink,
            arms={"L": (68 - 43 * sink, 8 + 10 * sink, 22, 35), "R": (80 - 47 * sink, 6 + 12 * sink, 18, 40)})
    legs(P, st, STANCE_FEET)
    if t <= D["buckle"]:
        st["off"].z += lift
        return st
    buckled_hips = {s: P.head(st, "DEF-thigh." + s) for s in "LR"}
    # Topple: the buckled pose turned forward around the pivot.
    fall = k([(D["buckle"], 0.0), (D["down"], 84.0), (0.88, 80.0), (1.0, 82.0)], t)
    R = rot(pitch=fall)
    hq = st["q"]["DEF-hips"]
    head = P.rest_head["DEF-hips"] + st["off"]
    st["q"]["DEF-hips"] = R @ hq
    st["off"] = D["pivot"] + R @ (head - D["pivot"]) - P.rest_head["DEF-hips"]
    st["off"].z += lift
    reach = k([(D["buckle"], 0.0), (0.7, 1.0), (1.0, 1.0)], t)
    upper_body(P, st, hunch=62 - 40 * reach, sway=6, head_pitch=2 - 30 * reach, head_roll=10 + 15 * reach,
            arms={"L": (25 + 140 * reach, 18 + 14 * reach, 22 - 15 * reach, 35), "R": (33 + 120 * reach, 18 + 20 * reach, 18, 40)},
            frame=R)
    # The legs straighten as the body goes down: IK towards ankles moved from the buckled stance to under
    # the hip joints, both in the body's frame before the fall, then carried round the pivot like the body.
    straight = k([(D["buckle"], 0.0), (D["down"], 1.0)], t)
    for s in "LR":
        x = 1 if s == "L" else -1
        hip = buckled_hips[s]
        a = STANCE_FEET[s][0].lerp(hip + Vector((0, 0.06, -0.78)), straight)
        P.ik(st, "DEF-thigh." + s, "DEF-shin." + s, D["pivot"] + R @ (a - D["pivot"]) + Vector((0, 0, lift)),
                R @ Vector((0.15 * x, -1, 0)))
        P.set_world(st, "DEF-foot." + s, R @ rot(pitch=60 * straight) @ STANCE_FEET[s][1])
    return st


def make_death(obj, rig, P):
    """The death clip, baked twice: the second pass lifts the body on each frame by how far the first went
    under the ground, and after the landing (t >= DEATH['down']) also lowers it onto the ground."""
    n = DEATH["frames"]
    act = K.bake(rig, P, "death_raw", n, lambda t: death_pose(P, t), loop=False)
    lifts = []
    for f in range(n + 1):
        low = K.lowest_point(obj, rig, act, f)
        t = f / n
        lifts.append(-low if (low < 0 or t >= DEATH["down"]) else 0.0)
    bpy_remove(act)
    lift_at = lambda t: lifts[min(int(round(t * n)), n)]
    return K.bake(rig, P, "death", n, lambda t: death_pose(P, t, lift_at(t)), loop=False), max(abs(x) for x in lifts)


def bpy_remove(act):
    import bpy
    bpy.data.actions.remove(act)


def main():
    import bpy
    K.reset_scene()
    rig = K.make_armature("zombie_rig", BONES)
    b = model()
    obj = b.build("zombie", PALETTE)
    blended = K.skin(obj, rig, b)
    P = K.Poser(rig)
    acts = {
        "idle": K.bake(rig, P, "idle", 90, lambda t: idle_pose(P, t)),
        "walk": K.bake(rig, P, "walk", WALK["frames"], lambda t: walk_pose(P, t)),
        "attack": K.bake(rig, P, "attack", ATTACK["frames"], lambda t: attack_pose(P, t), loop=False),
    }
    acts["death"], death_lift = make_death(obj, rig, P)
    # IK reach: how far a foot target was out of the leg's reach, worst pose of each clip.
    reach = {}
    for name, fn, n in (("idle", idle_pose, 90), ("walk", walk_pose, WALK["frames"]), ("attack", attack_pose, ATTACK["frames"])):
        worst = 0.0
        for f in range(n):
            st = P.new()
            st = fn(P, f / n)
            for s in "LR":
                target = walk_foot(s, f / n)[0] if name == "walk" else STANCE_FEET[s][0]
                worst = max(worst, (P.tail(st, "DEF-shin." + s) - target).length)
        reach[name] = round(worst, 4)
    # Checks on the deformed mesh.
    feet = {s: [i for i, o in enumerate(b.owner) if o == "DEF-foot." + s] for s in "LR"}
    fps = K.FPS
    speed = WALK["stride"] / (WALK["frames"] / fps)
    checks = {}
    torso = [list(f) for f, mi in zip(b.faces, b.mats) if b.owner[f[0]].startswith("DEF-spine")]
    arm_v = {s: [i for i, o in enumerate(b.owner) if o in ("DEF-forearm." + s, "DEF-hand." + s)] for s in "LR"}
    shin_v = {s: [i for i, o in enumerate(b.owner) if o in ("DEF-shin." + s, "DEF-foot." + s)] for s in "LR"}
    leg_p = {s: [list(f) for f in b.faces if b.owner[f[0]] in ("DEF-shin." + s, "DEF-foot." + s, "DEF-thigh." + s)] for s in "LR"}
    for name, act in acts.items():
        stance = (lambda s, t: walk_planted(s, t)) if name == "walk" else (lambda s, t: name != "death")
        c = K.measure(obj, rig, act, 90, feet, speed if name == "walk" else 0.0, stance)
        if name != "death":
            pairs = {"arm_in_torso_" + s: (arm_v[s], torso) for s in "LR"}
            pairs.update({"leg_in_leg_" + s: (shin_v[s], leg_p["R" if s == "L" else "L"]) for s in "LR"})
            c.update(K.crossings(obj, rig, act, 24, pairs))
        c["joints"] = K.joint_gaps(obj, rig, act, 24, b)
        c["ik_miss_m"] = reach.get(name, 0.0)
        checks[name] = c
    checks["weights"] = {"blended_vertices": blended}
    checks["death"]["ground_lift_max_m"] = round(death_lift, 4)
    height = max(Vector(v).z for v in b.verts)
    # The walk's measured contacts are its foot paths' (the feet land at their 'contact' times).
    clips = {
        "idle": {"duration_s": round(90 / fps, 4), "loop": True},
        "walk": {"duration_s": round(WALK["frames"] / fps, 4), "loop": True, "ground_speed_m_s": round(speed, 4),
                "stride_m": WALK["stride"], "left_contact": WALK["contact"]["L"], "right_contact": WALK["contact"]["R"]},
        "attack": {"duration_s": round(ATTACK["frames"] / fps, 4), "loop": False,
                "hit_s": round(ATTACK["hit"] * ATTACK["frames"] / fps, 4)},
        "death": {"duration_s": round(DEATH["frames"] / fps, 4), "loop": False},
    }
    for a in bpy.data.actions:
        a.use_fake_user = a.name in acts
    K.use_action(rig, acts["idle"])
    bpy.context.scene.frame_set(0)
    K.export(os.path.join(OUT, "zombie.glb"), [obj, rig])
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    K.write_json(os.path.join(OUT, "zombie_clips.json"), {"height_m": round(height, 4), "forward": "+z",
            "clips": clips, "checks": checks, "verts": len(obj.data.vertices), "tris": tris,
            "bones": len(rig.data.bones)})
    print("## zombie", {"height_m": round(height, 4), "verts": len(obj.data.vertices), "tris": tris, "checks": checks})


main()
