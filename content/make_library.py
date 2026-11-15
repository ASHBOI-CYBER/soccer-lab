#!/usr/bin/env python3
"""Soccer Lab's drill library: every drill is written here, by us, and exported to the app.

    python content/make_library.py      ->  writes SoccerMax/Resources/library.json and checks it

The app reads that one file at launch (Data/Library.swift) and crashes if a required field is missing, so this
script also checks everything the code relies on before it writes: the 20 drill ids the app's ready-made sessions
name (Data/Store.swift starter / starterSessions / fitnessSessions), unique ids, the "sets x reps" wording the app
parses, and the shape of each coach's-board diagram (UI/DrillBoard.swift).

To add a drill: add one D(...) entry below and run the script. Board coordinates are metres seen from above:
x to the right, z down the screen. The first player in a board is always "you".
"""
import json, math, os, re, sys

X = "×"   # the multiplication sign the app looks for in reps ("3 x 30 s" written with this sign)
PI = math.pi

# ---------------------------------------------------------------------------------------------------------------
# board helpers
# ---------------------------------------------------------------------------------------------------------------
def cone(x, z, c=None):
    """A disc cone; c = "red" / "blue" / "yellow" / "green" for drills that call colours (the app draws it that colour)."""
    d = {"k": "cone", "x": x, "z": z, "yaw": 0}
    if c: d["c"] = c
    return d
def goal(x=0, z=-8): return {"k": "goal", "x": x, "z": z, "yaw": 0}
def ladder(x, z, rungs=6): return {"k": "ladder", "x": x, "z": z, "yaw": 0, "rungs": rungs}
def hurdle(x, z, yaw=0): return {"k": "hurdle", "x": x, "z": z, "yaw": yaw}   # yaw 0: the bar lies across a run going up or down
def you(x=0, z=0, yaw=PI): return {"kit": "you", "x": x, "z": z, "yaw": round(yaw, 2)}
def run(*pts, both=False):
    p = {"pts": [list(q) for q in pts]}
    if both: p["both"] = True
    return p
def ball(*pts, both=False):
    p = {"pts": [list(q) for q in pts], "ball": True}
    if both: p["both"] = True
    return p
def board(props=(), players=None, balls=(), paths=()):
    return {"props": list(props), "players": players if players is not None else [you()],
            "balls": [list(b) for b in balls], "paths": list(paths)}

def spot(with_ball=True):
    """Work on one spot: you, a small square of cones to stay inside, the ball at your feet."""
    return board([cone(-1, -1), cone(1, -1), cone(-1, 1), cone(1, 1)], [you(0, 0.2)], [[0, -0.2]] if with_ball else [])
def wall(z=-3.0, half=2.0):
    """A wall across the top, centred on x = 0 (the app draws bricks; 2026-11-16, was a row of cones)."""
    return [{"k": "wall", "x": 0, "z": z, "yaw": 0, "w": half * 2}]
def lane(length=20.0, width=3.0):
    return [cone(-width / 2, 0), cone(width / 2, 0), cone(-width / 2, -length), cone(width / 2, -length)]
def mat():
    """Floor work with no ball: a mat-sized box and you in it."""
    return board([cone(-1, -0.6), cone(1, -0.6), cone(-1, 0.6), cone(1, 0.6)], [you(0, 0, PI / 2)])

# ---------------------------------------------------------------------------------------------------------------
# drills
# ---------------------------------------------------------------------------------------------------------------
DRILLS = []
def D(id, name, skill, level, min, reps, setup, how, points, stats, fixes, board, *, ball=True, gear=None, space="2 m square",
      progression=None, tags=None):
    gear = gear if gear is not None else (["Ball"] if ball else [])
    DRILLS.append({
        "id": id, "name": name, "skill": skill, "level": level, "who": "Solo", "min": min, "space": space,
        "gear": gear, "kit": [{"item": None, "label": g} for g in gear],
        "needs": ["Ball"] if ball else [],
        "setup": setup, "how": how, "reps": reps, "points": points, "progression": progression,
        "stats": stats, "fixes": fixes, "tags": tags or [], "video": False, "board": board,
    })

# ---- Ball mastery
D("toe-taps", "Toe Taps", "Ball mastery", 1, 3, f"3 {X} 30 s",
  "Stand over the ball in a small space.",
  ["Tap the top of the ball with the sole of one foot.", "Hop and swap so the other foot taps.",
   "Keep swapping in a steady rhythm, staying on the balls of your feet.", "Speed up only when the ball stays still."],
  ["Light touches: the ball should hardly move.", "Knees soft, arms out for balance.", "Eyes up for a second every few taps."],
  ["BC", "DRI"], ["Ball control", "First touch"], spot(),
  progression="Travel forward and backward while you tap.", tags=["warm-up", "quick feet"])
D("foundations", "Foundations", "Ball mastery", 1, 3, f"3 {X} 30 s",
  "Stand with the ball between your feet, feet a little wider than your hips.",
  ["Knock the ball from the inside of one foot to the inside of the other.", "Bounce lightly between every touch.",
   "Keep the ball moving side to side under your body.", "Count your touches and try to beat the count each set."],
  ["Use the inside of the foot, just below the ankle.", "Stay low with your knees bent.", "Small touches beat big ones."],
  ["BC", "DRI"], ["Ball control", "Weak foot"], spot(),
  progression="Move forward with the ball while it goes side to side.", tags=["warm-up", "both feet"])
D("sole-rolls", "Sole Rolls", "Ball mastery", 1, 3, f"3 {X} 30 s",
  "Stand side-on to the ball with one foot resting on top of it.",
  ["Roll the ball across your body with the sole of your foot.", "Stop it with the inside of the other foot.",
   "Roll it back the other way with the other sole.", "Keep going without letting the ball run away."],
  ["Roll, don't push: the sole stays in contact.", "Stay on your toes between rolls.", "Keep your chest over the ball."],
  ["BC"], ["Ball control"], spot(), progression="Add a step-over before each roll.")
D("figure-8", "Figure 8", "Ball mastery", 2, 4, f"3 {X} 45 s",
  "Put two cones about 2 m apart.",
  ["Dribble around one cone, then cut across the middle to the other.", "Go around the second cone the opposite way, so your path draws an 8.",
   "Use the inside of your foot to turn in and the outside to turn out.", "Change direction every set."],
  ["Many small touches as you go around a cone.", "Drop your shoulder into each turn.", "Use both feet: don't let one do all the work."],
  ["DRI", "BC"], ["Dribbling", "Weak foot", "Ball control"],
  board([cone(-1, 0), cone(1, 0)], [you(-1, 1.2, PI / 2)], [[-0.7, 1.2]],
        [run((-1, 1.2), (-2, 0), (-1, -1), (0, 0), (1, 1), (2, 0), (1, -1), (0, 0), (-1, 1.2))]),
  gear=["Ball", "2 cones"], space="4 m by 3 m", progression="Weak foot only.")
D("juggling", "Juggling", "Ball mastery", 2, 5, f"3 {X} 60 s",
  "Stand in open space with the ball in your hands.",
  ["Drop the ball and kick it up with your laces to waist height.", "Catch it. Repeat ten times on each foot.",
   "Now let it bounce once between kicks instead of catching.", "Then keep it up without the bounce and count."],
  ["Lock your ankle and point your toes slightly up.", "Keep the ball below your waist.", "Tiny steps to stay under it."],
  ["BC"], ["Ball control", "First touch", "Composure"], spot(),
  progression="Alternate feet, then add thighs.", tags=["touch", "anywhere"])
D("inside-outside", "Inside Outside", "Ball mastery", 2, 4, f"3 {X} 40 s",
  "Stand behind the ball with room to move a few steps forward.",
  ["Push the ball across with the inside of your right foot.", "Take it back with the outside of the same foot.",
   "Do that for five touches, then switch to the left.", "Then walk forward while you do it."],
  ["The ball stays within one step of you.", "Bend the standing knee.", "Keep the rhythm even on both feet."],
  ["BC", "DRI"], ["Ball control", "Weak foot"], spot(), progression="Jog forward for 10 m while you do it.")

# ---- Dribbling
D("cone-slalom", "Cone Slalom", "Dribbling", 2, 5, f"4 {X} 2 runs",
  "Put six cones in a line, one big step apart.",
  ["Dribble in and out of the cones to the end.", "Turn around the last cone and weave back.",
   "First set: right foot only. Second: left only.", "Last two sets: both feet, as quick as you can keep the ball close."],
  ["One touch between each pair of cones.", "Use the inside and the outside of the foot.", "Head up as you pass each cone."],
  ["DRI", "BC"], ["Dribbling", "Ball control", "1v1s"],
  board([cone(0, -z) for z in range(1, 7)], [you(0, 0.6)], [[0.2, 0.2]],
        [run((0, 0.6), (0.6, -1), (-0.6, -2), (0.6, -3), (-0.6, -4), (0.6, -5), (-0.6, -6), (0, -6.8))]),
  gear=["Ball", "6 cones"], space="8 m long", progression="Move the cones closer together.")
D("speed-dribble", "Speed Dribble", "Dribbling", 2, 4, f"3 {X} 4 runs",
  "Mark a 20 m lane with a cone at each end.",
  ["Dribble to the far cone at three-quarter speed.", "Push the ball ahead with your laces, one touch every two or three steps.",
   "Stop the ball dead on the far line with your sole.", "Walk back and go again, a little faster."],
  ["Bigger touches in open space, small ones near the line.", "Lean forward and run on your toes.", "Look up between touches."],
  ["DRI", "PHY"], ["Dribbling", "Speed"],
  board(lane(), [you(0, 0.6)], [[0, 0.2]], [run((0, 0.6), (0, -20))]),
  gear=["Ball", "4 cones"], space="20 m lane", progression="Race a timer and try to beat it.")
D("stop-and-go", "Stop and Go", "Dribbling", 3, 4, f"3 {X} 4 runs",
  "Mark a 15 m lane with a cone in the middle.",
  ["Dribble toward the middle cone at jogging speed.", "At the cone, stop the ball with your sole for a split second.",
   "Explode away with a big first touch.", "Slow down again before the end and walk back."],
  ["The change of speed is the move: slow, stop, fast.", "Push off the foot that is behind you.", "First touch after the stop goes past the cone, not into it."],
  ["DRI", "PHY"], ["1v1s", "Dribbling", "Speed"],
  board([cone(-1.5, 0), cone(1.5, 0), cone(0, -7), cone(-1.5, -15), cone(1.5, -15)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -6.4)), run((0.6, -7.2), (0.6, -15))]),
  gear=["Ball", "5 cones"], space="15 m lane", progression="Add a body feint before you go.")

# ---- First touch and passing
D("wall-passes", "Wall Passes", "Passing", 1, 5, f"3 {X} 20 passes",
  "Stand 3 m from a wall or a rebounder.",
  ["Pass the ball firmly against the wall with the inside of your foot.", "Control the rebound with one touch.",
   "Pass again with your second touch.", "Swap feet every ten passes."],
  ["Plant your standing foot beside the ball, pointing at the target.", "Strike through the middle of the ball.", "Be on your toes before the ball comes back."],
  ["PAS", "BC"], ["Passing", "First touch", "Weak foot"],
  board(wall(), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -2.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 4 m", progression="One touch only: pass it straight back.")
D("wall-first-touch", "Open-Up Touch", "First touch", 2, 5, f"3 {X} 12 passes",
  "Stand 4 m from a wall with a cone 2 m to each side of you.",
  ["Pass against the wall.", "Take your first touch sideways, toward one of the cones.",
   "Dribble around that cone and pass again.", "Go to the other cone next time."],
  ["Open your hips so the touch takes you where you want to go.", "First touch travels about a metre, no more.", "Check your shoulder before the ball arrives."],
  ["BC", "PAS"], ["First touch", "Ball control", "Vision"],
  board(wall(-4) + [cone(-2, 0), cone(2, 0)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -3.8), both=True), run((0, 0.4), (-2, 0.6), (-2.6, 0), (-2, -0.6))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 5 m", progression="Take the touch with the foot furthest from the ball.")
D("weak-foot-laces", "Weak Foot Strikes", "Passing", 2, 5, f"3 {X} 10 passes",
  "Stand 5 m from a wall. Use your weaker foot only.",
  ["Roll the ball a step in front of you.", "Strike it against the wall with the laces of your weaker foot.",
   "Trap the rebound with the same foot.", "Reset and go again."],
  ["Toes down, ankle locked.", "Lean over the ball so it stays low.", "Follow through toward the target."],
  ["PAS", "SHO"], ["Weak foot", "Passing", "Shooting"],
  board(wall(-5), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -4.8))]),
  gear=["Ball", "Wall"], space="A wall and 6 m", progression="Step back to 8 m.")
D("long-pass-target", "Long Pass to a Target", "Passing", 3, 6, f"3 {X} 8 passes",
  "Put two cones 2 m apart as a gate, 20 m away.",
  ["Take a short run-up from a slight angle.", "Strike the bottom half of the ball with the inside of your laces.",
   "Try to land it through the gate.", "Fetch it, dribble back and go again."],
  ["Standing foot beside the ball, a little behind it.", "Lean back slightly to lift it.", "Finish with your kicking leg high."],
  ["PAS"], ["Long balls", "Passing", "Crossing"],
  board([cone(-1, -20), cone(1, -20)], [you(0.6, 0.6)], [[0, 0]], [ball((0, 0), (0, -20))]),
  gear=["Ball", "2 cones"], space="25 m", progression="Make the gate 1 m wide.")

# ---- Shooting
D("laces-strike", "Laces Strike", "Shooting", 2, 6, f"3 {X} 8 shots",
  "Put the ball 12 m from a goal or a marked target on a wall.",
  ["Take three steps back and one to the side.", "Run up and plant your standing foot beside the ball.",
   "Strike the middle of the ball with your laces.", "Land on your kicking foot."],
  ["Head and chest over the ball.", "Ankle locked, toes pointing down.", "Aim for a corner, not the middle."],
  ["SHO"], ["Shooting", "Finishing"],
  board([goal(0, -12)], [you(0.8, 1.2)], [[0, 0]], [run((0.8, 1.2), (0.2, 0.2)), ball((0, 0), (-2.6, -12))]),
  gear=["Ball", "Goal or wall target"], space="15 m and a goal", progression="Shoot after one touch out of your feet.")
D("touch-and-finish", "Touch and Finish", "Shooting", 3, 6, f"3 {X} 6 shots",
  "Put a cone 14 m from goal. Start 4 m behind it with the ball.",
  ["Dribble at the cone.", "Take a touch past it to one side.", "Shoot with your next touch.", "Alternate sides."],
  ["The touch past the cone sets up the shot: not too close to your feet.", "Pick your corner before you shoot.", "Low and hard beats high and hopeful."],
  ["SHO", "DRI"], ["Finishing", "Shooting", "1v1s"],
  board([goal(0, -14), cone(0, 0)], [you(0, 4)], [[0, 3.6]],
        [run((0, 4), (0, 0.8), (1.4, -1)), ball((1.4, -1), (3, -14))]),
  gear=["Ball", "Goal or wall target", "1 cone"], space="20 m and a goal", progression="Finish with your weaker foot.")

# ---- Defending, awareness, goalkeeping
D("jockey-shuffle", "Jockey Shuffle", "Defending", 2, 4, f"3 {X} 30 s",
  "Put two cones 6 m apart. No ball needed.",
  ["Stand side-on between the cones, knees bent.", "Shuffle backward and sideways toward one cone.",
   "Touch level with the cone, then switch your front foot and go to the other.", "Stay low the whole time."],
  ["Side-on, never square.", "Small quick steps: feet never cross.", "Weight on the balls of your feet."],
  ["DEF", "PHY"], ["Defending", "Positioning", "1v1s"],
  board([cone(-3, 0), cone(3, 0)], [you(0, 0, PI / 2)], [], [run((-2.6, 0), (2.6, 0), both=True)]),
  ball=False, gear=["2 cones"], space="6 m wide", progression="Have someone point left or right and react.")
D("recovery-run", "Recovery Run", "Defending", 3, 5, f"3 {X} 4 runs",
  "Put a cone 15 m away and a second one 5 m to its side. No ball needed.",
  ["Face away from the cones.", "Turn and sprint to the far cone.", "Slow down in the last three steps and get side-on.",
   "Shuffle across to the second cone, then walk back."],
  ["Turn with a drop step, not a spin on the spot.", "Chop your steps as you arrive.", "Finish low and balanced, ready to tackle."],
  ["DEF", "PHY"], ["Defending", "Speed", "Positioning"],
  board([cone(0, -15), cone(5, -15)], [you(0, 0, 0)], [], [run((0, 0), (0, -14.4)), run((0.4, -15), (4.6, -15))]),
  ball=False, gear=["2 cones"], space="15 m", progression="Start lying on your front.")
D("scan-and-turn", "Scan and Turn", "Awareness", 2, 5, f"3 {X} 10 passes",
  "Stand 4 m from a wall with a cone 3 m behind you on each side.",
  ["Pass against the wall.", "While the ball is travelling, look over your shoulder at a cone.",
   "Receive on the half turn and dribble to the cone you looked at.", "Come back and repeat, looking the other way."],
  ["Look before the ball arrives, not after.", "Receive with your back foot.", "Say the colour or side out loud to prove you looked."],
  ["PAS", "BC"], ["Vision", "First touch", "Composure"],
  board(wall(-4) + [cone(-2.5, 3), cone(2.5, 3)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -3.8), both=True), run((0, 0.4), (2.2, 2.7))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 8 m", progression="Take one touch to turn, the next to pass.")
D("gk-set-and-catch", "Set and Catch", "Goalkeeping", 1, 5, f"3 {X} 12 catches",
  "Stand 3 m from a wall with the ball in your hands.",
  ["Throw the ball against the wall at chest height.", "Take a small step and set your feet before it comes back.",
   "Catch it with your hands behind the ball, thumbs together.", "Bring it into your chest."],
  ["Set position: feet shoulder width, knees bent, hands ready.", "Watch the ball all the way into your hands.", "Soft elbows take the pace off."],
  ["DEF", "BC"], ["Positioning", "Composure"],
  board(wall(), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -2.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 4 m", progression="Throw it lower and scoop it up.")

D("gk-low-dive", "Low Dive", "Goalkeeping", 2, 5, f"3 {X} 6 each side",
  "Kneel on soft ground with a ball a step to one side. Move to standing only when the kneeling version feels easy.",
  ["From your knees, fall sideways toward the ball.", "Lead with your hands: bottom hand behind the ball, top hand on top.",
   "Land on your side, never your elbow or your front.", "Get up quickly and reset. Swap sides."],
  ["Step toward the ball before you go down.", "Hands reach the ball before your body reaches the ground.", "Keep your eyes on the ball until it is trapped."],
  ["DEF", "PHY"], ["Positioning", "Composure"],
  board([cone(-2, -1), cone(2, -1)], [you(0, 0.2)], [[1.4, 0]], [run((0, 0.2), (1.2, 0.1))]),
  gear=["Ball", "2 cones"], space="Soft ground, 4 m wide", progression="Start standing, with a small side step before the dive.")
D("gk-angle-shuffle", "Angle Shuffle", "Goalkeeping", 2, 4, f"3 {X} 40 s",
  "Mark a goal with two cones 5 m apart. Put three balls in an arc 8 m out: left, middle and right.",
  ["Start in the middle of the goal in your set position.", "Shuffle so you stand on the line between the left ball and the centre of the goal.",
   "Set your feet, then shuffle to line up with the middle ball, then the right one.", "Keep moving across the arc and back."],
  ["Small side steps: your feet never cross.", "Be set and still before you count a ball as covered.", "Stay a step or two off your line, not on it."],
  ["DEF", "PHY"], ["Positioning"],
  board([cone(-2.5, 0), cone(2.5, 0)], [you(0, -0.8, PI)], [[-4, -7], [0, -8], [4, -7]], [run((-1.4, -0.9), (1.4, -0.9), both=True)]),
  gear=["Ball", "2 cones"], space="10 m in front of a goal", progression="Have someone call left, middle or right at random.")

D("check-and-go", "Check and Go", "Awareness", 2, 4, f"3 {X} 6 runs",
  "Put a cone where a defender would stand, and two more 8 m away to each side of it. No ball needed.",
  ["Stand next to the defender cone.", "Take three sharp steps one way, as if asking for the ball there.",
   "Plant your foot and sprint the other way to the far cone.", "Walk back. Go the opposite way next time."],
  ["The first move has to look real: sell it with your whole body.", "Change direction off your outside foot.", "Look back at where the ball would be as you sprint."],
  ["PHY", "DRI"], ["Positioning", "Speed"],
  board([cone(0, 0), cone(-8, -2), cone(8, -2)], [you(0.6, 0.4, PI / 2)], [], [run((0.6, 0.4), (2.4, 0.8)), run((2.4, 0.8), (-8, -1.6))]),
  ball=False, gear=["3 cones"], space="16 m wide", progression="Have a friend pass you a ball as you arrive.")
D("shield-and-turn", "Shield and Turn", "Ball mastery", 2, 4, f"3 {X} 40 s",
  "Put one cone down as a defender. Stand with your back to it and the ball at your feet.",
  ["Get side-on to the cone with your arm out toward it.", "Keep the ball on the foot furthest from the cone, under your sole.",
   "Roll the ball around as you shuffle, always keeping your body between it and the cone.", "After a few seconds, turn away from the cone and take two touches clear."],
  ["Low and wide: knees bent, feet apart.", "The ball stays on your far foot.", "Feel where the defender is with your arm, not by looking."],
  ["BC", "PHY"], ["Ball control", "Strength", "Composure"],
  board([cone(0, -0.8), cone(-2, 2), cone(2, 2)], [you(0, 0, PI / 2)], [[0.3, 0.4]], [run((0, 0), (1.8, 1.8))]),
  gear=["Ball", "3 cones"], space="4 m square", progression="Ask a friend to lean on you while you shield.")
D("one-touch-wall", "One-Touch Wall", "Passing", 3, 4, f"3 {X} 30 passes",
  "Stand 2 m from a wall.",
  ["Pass against the wall and play the rebound straight back, first time.", "Alternate feet: right, left, right, left.",
   "Count how many you get without stopping the ball.", "If it gets away, reset and start the count again."],
  ["Stay on your toes and keep your feet moving.", "Firm ankle, soft knees.", "Hit the middle of the ball so it comes back along the ground."],
  ["PAS", "BC"], ["Passing", "First touch", "Weak foot"],
  board(wall(-2), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -1.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 3 m", progression="Step back to 4 m and keep it first time.")
D("press-and-recover", "Press and Recover", "Defending", 3, 5, f"3 {X} 5 runs",
  "Put one cone 10 m in front of you and another 10 m behind you. No ball needed.",
  ["Sprint to the front cone as if closing down a player.", "Slow down over the last two steps and finish side-on, low.",
   "Hold for one second, then turn and sprint back past the start to the far cone.", "Walk back to the middle and go again."],
  ["Fast to get there, slow to arrive.", "Never run straight through: arrive balanced.", "The turn back is as important as the press."],
  ["DEF", "PHY"], ["Defending", "Stamina", "Positioning"],
  board([cone(0, -10), cone(0, 10)], [you(0, 0)], [], [run((0, 0), (0, -9.4)), run((0.6, -9.4), (0.6, 9.6))]),
  ball=False, gear=["2 cones"], space="20 m", progression="Add a side shuffle of 3 m before you recover.")
D("gk-throw-target", "Throw to a Target", "Goalkeeping", 2, 5, f"3 {X} 8 throws",
  "Put two cones 2 m apart as a gate, 15 m away. Stand with the ball in your hands.",
  ["Step forward with the foot opposite your throwing arm.", "Bring your arm over the top, straight, like a bowler.",
   "Release so the ball skims the ground through the gate.", "Fetch it and go again. Swap arms halfway."],
  ["Point your front shoulder at the target.", "A flat, fast ball is easier for your teammate than a looping one.", "Follow through toward the gate."],
  ["PAS", "DEF"], ["Passing", "Long balls"],
  board([cone(-1, -15), cone(1, -15)], [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -15))]),
  gear=["Ball", "2 cones"], space="20 m", progression="Move the gate to 25 m, or roll it underarm for short ones.")

# ---- Runs (no ball)
D("strides", "Strides", "Runs", 1, 4, f"4 {X} 60 m", "Mark out about 60 m of flat ground.",
  ["Build up smoothly over the first 20 m.", "Hold a fast, relaxed pace for the middle 20 m.", "Ease off over the last 20 m.", "Walk back to recover."],
  ["Tall posture, relaxed shoulders.", "Fast but never straining: about 80 percent.", "Land under your hips, not out in front."],
  ["PHY"], ["Speed", "Stamina"],
  board(lane(24, 3), [you(0, 0.6)], [], [run((0, 0.6), (0, -24))]),
  ball=False, gear=["2 cones"], space="60 m", tags=["warm-up"])
D("flying-20s", "Flying 20s", "Runs", 3, 5, f"4 {X} 20 m", "Mark three cones in a line: start, 20 m and 40 m.",
  ["Jog, then build speed up to the middle cone.", "Sprint flat out from the middle cone to the last one.",
   "Slow down gradually after the last cone.", "Walk back and rest a full minute."],
  ["Be at top speed as you reach the middle cone.", "Drive your arms from hip to cheek.", "Quality only: stop when you slow down."],
  ["PHY"], ["Speed"],
  board([cone(-1.5, 0), cone(1.5, 0), cone(-1.5, -12), cone(1.5, -12), cone(-1.5, -24), cone(1.5, -24)], [you(0, 0.6)], [],
        [run((0, 0.6), (0, -11.6)), run((0, -12.4), (0, -24))]),
  ball=False, gear=["3 cones"], space="50 m")
D("diagonals", "Diagonals", "Runs", 2, 6, f"3 {X} 4 runs", "Use a pitch or any big rectangle of grass.",
  ["Run corner to corner along the diagonal at a steady, strong pace.", "Walk along the short side to the next corner.",
   "Run the other diagonal.", "That is two runs. Keep going."],
  ["Same pace on every run.", "Breathe in rhythm with your steps.", "Use the walk to get your breath back fully."],
  ["PHY"], ["Stamina"],
  board([cone(-6, 0), cone(6, 0), cone(-6, -16), cone(6, -16)], [you(-6, 0.6)], [],
        [run((-6, 0.6), (6, -16)), run((6, -16), (-6, -16)), run((-6, -16), (6, 0))]),
  ball=False, gear=[], space="Half a pitch")
D("high-knee-runs", "High Knee Runs", "Runs", 1, 3, f"3 {X} 20 m", "Mark out a 20 m lane.",
  ["Run forward lifting each knee to hip height.", "Take short, quick steps: this is about rhythm, not speed.",
   "Pump your arms in time with your legs.", "Walk back."],
  ["Stay tall: don't lean back.", "Land on the balls of your feet.", "Quick off the ground."],
  ["PHY"], ["Speed"],
  board(lane(12, 3), [you(0, 0.6)], [], [run((0, 0.6), (0, -12))]),
  ball=False, gear=["2 cones"], space="20 m", tags=["warm-up"])
D("repeat-sprints", "Repeat Sprints", "Runs", 4, 6, f"2 {X} 6 runs", "Put two cones 30 m apart.",
  ["Sprint to the far cone.", "Jog back in about 20 seconds.", "Go again straight away.", "Rest two minutes between sets."],
  ["Every sprint is a full sprint.", "Stay relaxed in your face and hands.", "If your time drops a lot, end the set."],
  ["PHY"], ["Stamina", "Speed"],
  board(lane(24, 3), [you(0, 0.6)], [], [run((0, 0.6), (0, -24), both=True)]),
  ball=False, gear=["2 cones"], space="30 m")

# ---- Core and stretching (no ball)
D("dead-bug", "Dead Bug", "Core", 1, 3, f"3 {X} 10 each side", "Lie on your back with arms straight up and knees bent above your hips.",
  ["Press your lower back into the ground.", "Slowly lower one arm behind your head and straighten the opposite leg.",
   "Bring them back to the start.", "Repeat on the other side."],
  ["Your lower back stays down the whole time.", "Move slowly: about three seconds each way.", "Breathe out as you reach."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat")
D("front-plank", "Front Plank", "Core", 1, 3, f"3 {X} 30 s", "Lie face down, then rise onto your forearms and toes.",
  ["Elbows under your shoulders.", "Lift your hips so your body makes one straight line.", "Squeeze your stomach and the backs of your legs.", "Hold."],
  ["No sagging hips, no high hips.", "Look at the ground just ahead of your hands.", "Keep breathing."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Lift one foot for the last ten seconds.")
D("side-plank", "Side Plank", "Core", 2, 3, f"2 {X} 25 s each side", "Lie on your side, propped on one forearm, feet stacked.",
  ["Elbow under your shoulder.", "Lift your hips until your body is straight from head to feet.", "Hold.", "Swap sides."],
  ["Hips stay high and stacked.", "Push the ground away with your forearm.", "Don't let your top shoulder roll forward."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat")
D("glute-bridge", "Glute Bridge", "Core", 1, 3, f"3 {X} 12", "Lie on your back with knees bent and feet flat, hip width apart.",
  ["Push through your heels and lift your hips.", "Stop when your knees, hips and shoulders are in line.",
   "Squeeze for one second.", "Lower slowly."],
  ["Drive through the heels, not the toes.", "Don't arch your lower back at the top.", "Knees stay in line with your feet."],
  ["PHY"], ["Strength", "Speed"], mat(), ball=False, gear=[], space="A mat", progression="One leg at a time.")
D("mountain-climbers", "Mountain Climbers", "Core", 2, 3, f"3 {X} 25 s", "Start in a press-up position, hands under your shoulders.",
  ["Drive one knee toward your chest.", "Switch legs quickly, as if running on the spot.", "Keep your hips level with your shoulders.", "Go for the full time."],
  ["Hands stay planted under the shoulders.", "Hips low: don't let them bounce up.", "Fast feet, steady upper body."],
  ["PHY"], ["Stamina", "Strength"], mat(), ball=False, gear=[], space="A mat")
D("plank-shoulder-taps", "Plank Shoulder Taps", "Core", 2, 3, f"3 {X} 16 taps", "Start in a press-up position with your feet a little wider than your hips.",
  ["Lift one hand and tap the opposite shoulder.", "Put it back down.", "Tap with the other hand.", "Keep alternating."],
  ["Hips stay still: imagine a cup of water on your back.", "Wider feet make it easier to stay steady.", "Slow is harder and better."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat")
D("walking-knee-hug", "Walking Knee Hug", "Stretching", 1, 2, f"2 {X} 10 each side", "Find 10 m of space to walk.",
  ["Step forward and lift one knee.", "Hug it to your chest with both hands for a second.", "Step through and do the other leg.", "Keep walking."],
  ["Stand tall on the standing leg.", "Rise onto your toes as you hug.", "Smooth, not rushed."],
  ["PHY"], ["Speed"],
  board(lane(8, 2), [you(0, 0.6)], [], [run((0, 0.6), (0, -8))]),
  ball=False, gear=[], space="10 m", tags=["warm-up"])
D("hamstring-sweep", "Hamstring Sweep", "Stretching", 1, 2, f"2 {X} 10 each side", "Find 10 m of space to walk.",
  ["Step one heel out in front with that leg straight and toes up.", "Bend the back knee and sit your hips back.",
   "Sweep both hands down past your front foot.", "Stand, step and swap legs."],
  ["Flat back as you reach.", "Feel the stretch behind the front thigh.", "Keep moving: don't hold."],
  ["PHY"], ["Speed"],
  board(lane(8, 2), [you(0, 0.6)], [], [run((0, 0.6), (0, -8))]),
  ball=False, gear=[], space="10 m", tags=["warm-up", "cool-down"])
D("hip-flexor-stretch", "Hip Flexor Stretch", "Stretching", 1, 2, f"2 {X} 30 s each side", "Kneel on one knee with the other foot flat in front of you.",
  ["Tuck your hips under.", "Gently push your hips forward until you feel a stretch at the front of the back hip.",
   "Reach the arm on that side up.", "Hold, then swap."],
  ["Stay tall: don't lean forward.", "Squeeze the back glute.", "Ease into it and breathe."],
  ["PHY"], ["Speed"], mat(), ball=False, gear=[], space="A mat", tags=["cool-down"])

# ===============================================================================================================
# the second batch (2026-11): more drills for every skill, same rules as above
# ===============================================================================================================
SQUARE = [cone(-1, -1), cone(1, -1), cone(-1, 1), cone(1, 1)]   # the small square of cones spot() uses

# ---- Ball mastery
D("pull-push", "Pull and Push", "Ball mastery", 1, 3, f"3 {X} 30 s",
  "Stand behind the ball with one foot resting on top of it.",
  ["Pull the ball back toward you with the sole of your foot.", "As it rolls, push it forward again with your laces.",
   "Keep the ball moving a little way forward and back.", "Swap feet every ten touches."],
  ["Sole pulls, laces push: two touches, one rhythm.", "Stay on the toes of your standing foot.", "Keep it close: never more than a step away."],
  ["BC", "DRI"], ["Ball control", "Weak foot"],
  board(SQUARE, [you(0, 0.5)], [[0, -0.1]], [ball((0, -0.5), (0, 0.2), both=True)]),
  progression="Pull back, then push out to the side, and travel round a square.", tags=["warm-up", "quick feet"])
D("tap-turn-circle", "Tap Turn Circle", "Ball mastery", 1, 3, f"3 {X} 30 s",
  "Stand over the ball inside a small square of cones.",
  ["Do toe taps on top of the ball, swapping feet.", "With each tap, take a small step around the ball.",
   "Go all the way round in a circle, then go the other way.", "Keep the ball in the same spot the whole time."],
  ["The ball stays still: you move round it.", "Light taps with the front of the sole.", "Look up as you go round."],
  ["BC", "DRI"], ["Ball control", "Composure"],
  board(SQUARE, [you(0, 0.4)], [[0, -0.2]], [run((0, 0.4), (0.6, -0.2), (0, -0.8), (-0.6, -0.2), (-0.15, 0.35))]),
  progression="Go round twice as fast without moving the ball.", tags=["warm-up", "quick feet"])
D("step-over-shuffle", "Step-Over Shuffle", "Ball mastery", 2, 3, f"3 {X} 30 s",
  "Stand behind the ball with your feet either side of it, a little apart.",
  ["Circle your right foot round the front of the ball, from inside to outside, without touching it.",
   "Land it beside the ball and do the same with your left.", "Keep alternating in a quick, bouncy rhythm.",
   "Every fifth step-over, push the ball a step to the side and carry on."],
  ["Swing the foot round the ball, not over the top of it.", "Dip your shoulder with each step-over to sell it.", "Stay low and bouncy."],
  ["DRI", "BC"], ["Dribbling", "1v1s"], spot(),
  progression="Travel forward slowly while you do them.", tags=["quick feet"])
D("v-pull-backs", "V Pull-Backs", "Ball mastery", 2, 4, f"3 {X} 40 s",
  "Stand behind the ball with room for a step to each side.",
  ["Put your sole on the ball and pull it back toward you.", "Push it out at an angle with the inside of the same foot.",
   "Your two touches make the shape of a V.", "Swap feet and make a V on the other side."],
  ["Pull back first, then push away: two clean touches.", "Turn your hips as the ball goes out.", "Keep the V small and quick."],
  ["BC", "DRI"], ["Ball control", "Dribbling", "Weak foot"],
  board([cone(-1.5, -1), cone(1.5, -1), cone(-1.5, 1), cone(1.5, 1)], [you(0, 0.7)], [[0, 0.2]],
        [ball((-1, -0.5), (0, 0.3), (1, -0.5))]),
  space="3 m square", progression="Add a step-over between each V.")
D("sole-roll-shuffle", "Sole Roll Shuffle", "Ball mastery", 2, 4, f"3 {X} 40 s",
  "Put two cones 5 m apart. Start at one with the ball beside you.",
  ["Roll the ball sideways across your body with the sole of your foot.", "Step after it so you travel toward the other cone.",
   "Keep rolling with the same foot until you reach the cone.", "Come back the other way using the other foot."],
  ["Small rolls: the ball stays right under your foot.", "Hop on your standing foot as you go.", "Keep facing forward: you move sideways."],
  ["BC", "DRI"], ["Ball control", "Weak foot"],
  board([cone(-2.5, 0), cone(2.5, 0)], [you(-2, 0.5)], [[-1.6, 0.1]], [run((-2, 0.9), (2, 0.9), both=True)]),
  gear=["Ball", "2 cones"], space="6 m wide", progression="Roll with the sole, stop it with the inside of the other foot, and keep going.",
  tags=["both feet"])
D("sole-circles", "Sole Circles", "Ball mastery", 3, 4, f"3 {X} 30 s",
  "Stand over the ball in a small space, one foot resting on it.",
  ["Start with the ball just in front of your standing foot.", "Roll it round the outside of your standing foot, then behind it.",
   "Bring it back round to the front with small sole touches.", "Do three circles one way and three the other, then swap feet."],
  ["Hop on the standing foot so it moves out of the ball's way.", "Many small rolls, not one big one.", "Use your arms for balance."],
  ["BC"], ["Ball control", "Composure"],
  board(SQUARE, [you(0, 0.1)], [[0.3, -0.35]], [ball((0.3, -0.35), (0.5, 0.4), (-0.3, 0.6), (-0.5, -0.3), (0.15, -0.45))]),
  progression="Do it with your eyes up, looking at a spot in front of you.")
D("thigh-juggles", "Thigh Juggles", "Ball mastery", 3, 5, f"3 {X} 60 s",
  "Stand in open space with the ball in your hands.",
  ["Drop the ball onto your thigh and pop it up to chest height.", "Catch it, then do the same on the other thigh.",
   "Now keep it up: right thigh, left thigh, without catching.", "Mix in a foot touch every few thigh touches."],
  ["Hit the ball with the middle of the thigh, knee bent at a right angle.", "Lift the knee to the ball: don't wait for it to drop.", "Small pops, not high ones."],
  ["BC"], ["Ball control", "First touch"], spot(),
  progression="Thigh, foot, thigh, foot on the same leg, then swap.", tags=["touch", "anywhere"])
D("croqueta-rhythm", "Croqueta Rhythm", "Ball mastery", 4, 4, f"3 {X} 40 s",
  "Put four cones in a line, 2 m apart.",
  ["Dribble slowly toward the first cone.", "Just before it, shift the ball sideways from the inside of one foot to the inside of the other.",
   "Carry it past the cone on that side and dribble on to the next one.", "Shift the other way at the next cone. Keep going to the end."],
  ["Two quick touches: one to shift, one to go.", "The ball moves sideways and your body moves with it.", "Go faster only when the ball stays close."],
  ["DRI", "BC"], ["Dribbling", "1v1s", "Weak foot"],
  board([cone(0, -2), cone(0, -4), cone(0, -6), cone(0, -8)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -1), (0.7, -2), (0, -3), (-0.7, -4), (0, -5), (0.7, -6), (0, -7), (-0.7, -8), (0, -9))]),
  gear=["Ball", "4 cones"], space="10 m long", progression="Do it at speed, with your eyes up at each cone.")
D("juggling-ladder", "Juggling Ladder", "Ball mastery", 4, 6, f"3 {X} 2 min",
  "Stand in open space with the ball.",
  ["Juggle ten with your right foot only.", "Then ten with your left foot only.", "Then ten swapping right and left.",
   "Then ten using feet and thighs. If the ball drops, start that step again."],
  ["Lock your ankle and keep touches below your waist.", "Count out loud: it keeps the rhythm.", "Small steps between touches to stay under the ball."],
  ["BC"], ["Ball control", "First touch", "Weak foot"], spot(),
  progression="Add a step of ten head touches at the end.", tags=["touch", "anywhere"])
D("minute-combo", "Minute Combo", "Ball mastery", 5, 5, f"4 {X} 60 s",
  "Stand over the ball in a small square of cones.",
  ["Do 8 toe taps, then 8 sole rolls across your body.", "Then 8 pull and pushes, then 8 step-overs.",
   "Go straight from one move into the next without stopping.", "Repeat the chain until the minute is up. Count the full chains."],
  ["The switch between moves is the hard part: keep it smooth.", "Speed comes from quick feet, not big touches.", "If you lose the ball, get it back and carry on."],
  ["BC", "DRI"], ["Ball control", "Dribbling", "Composure"], spot(),
  progression="Start each chain with your weaker foot.", tags=["quick feet"])

# ---- Dribbling
D("coach-calls", "Coach Calls", "Dribbling", 2, 4, f"3 {X} 60 s",
  "Mark a 6 m square with four cones. Prop your phone up nearby with the sound on.",
  ["Dribble around inside the square with small touches.",
   "Every few seconds the phone calls a move: Cruyff, step-over, drag back, scissors, inside cut or sole roll.",
   "Do that move straight away, then keep dribbling.", "Stay inside the square the whole time."],
  ["Keep the ball close so you can do any move at once.", "React to the call: no waiting to get set.", "Head up between calls."],
  ["DRI", "BC"], ["Dribbling", "1v1s", "Composure"],
  board([cone(-3, -3), cone(3, -3), cone(-3, 3), cone(3, 3)], [you(-1, 1)], [[-0.6, 0.7]],
        [run((-1, 1), (1.5, 0.5), (1, -1.8), (-1.5, -1), (-1.8, 1.6))]),
  gear=["Ball", "4 cones"], space="6 m square", progression="Faster calls, or do every move with your weaker foot.", tags=["quick feet"])
D("box-dribble", "Box Dribble", "Dribbling", 1, 4, f"4 {X} 2 laps",
  "Put four cones in a square, 4 m apart.",
  ["Dribble around the outside of the square.", "Use the inside of your foot to turn at each cone.",
   "After two laps, go the other way so the other foot does the turning.", "Keep the ball close as you go round each cone."],
  ["Slow down a little into each corner, speed up out of it.", "Small touches at the cones, bigger ones on the straights.", "Look up on the straights."],
  ["DRI", "BC"], ["Dribbling", "Ball control"],
  board([cone(-2, -2), cone(2, -2), cone(-2, 2), cone(2, 2)], [you(-2.6, 2.6)], [[-2.6, 2.2]],
        [run((-2.6, 2.6), (-2.6, -2.6), (2.6, -2.6), (2.6, 2.6), (-2.2, 2.6))]),
  gear=["Ball", "4 cones"], space="5 m square", progression="Turn with the outside of the foot instead.", tags=["warm-up"])
D("gate-hunt", "Gate Hunt", "Dribbling", 1, 4, f"3 {X} 45 s",
  "Make five gates by putting pairs of cones 1 m apart, spread around a 10 m square.",
  ["Dribble through any gate.", "Then find another gate and dribble through that one.",
   "You can't use the same gate twice in a row.", "Count how many gates you get before the time is up."],
  ["Look up to find the next gate before you finish the last one.", "Turn sharply after each gate.", "Small touches just before a gate, a bigger one after."],
  ["DRI", "BC"], ["Dribbling", "Vision", "Ball control"],
  board([cone(-3.5, 3), cone(-2.5, 3), cone(0, 0), cone(0, -1), cone(2, -4), cone(3, -4), cone(-4, -3.5), cone(-3, -3.5),
         cone(3.5, 2.5), cone(3.5, 3.5)], [you(-1, 4.6)], [[-1.3, 4.2]],
        [run((-1, 4.6), (-3, 3.6), (-3, 2.4), (-0.6, -0.5), (0.6, -0.5), (2.5, -3.4), (2.5, -4.6))]),
  gear=["Ball", "10 cones"], space="10 m square", progression="Weaker foot only, or make the gates smaller.", tags=["warm-up"])
D("cut-and-go", "Inside Cut and Go", "Dribbling", 2, 4, f"3 {X} 4 runs",
  "Put a cone 8 m in front of you, and two more 5 m beyond it, one to each side.",
  ["Dribble at the middle cone at a jog.", "One step before it, cut the ball sideways with the inside of your foot.",
   "Push off hard and sprint with the ball to the cone on that side.", "Walk back. Cut the other way next time."],
  ["Sell it: lean as if you're going straight on.", "Cut across your body, then go.", "The speed after the cut is what beats a defender."],
  ["DRI", "PHY"], ["Dribbling", "1v1s", "Speed"],
  board([cone(0, -8), cone(-4, -13), cone(4, -13)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -7)), run((0, -7), (-0.9, -7.6), (-3.8, -12.4))]),
  gear=["Ball", "3 cones"], space="15 m", progression="Cut with your weaker foot both ways.")
D("zigzag-cuts", "Zigzag Cuts", "Dribbling", 2, 5, f"3 {X} 2 runs",
  "Put six cones in a zigzag, each one 3 m on from the last and 2 m to the side.",
  ["Dribble to the first cone.", "Cut the ball across with the outside of your foot and go to the next.",
   "At the next cone, cut back with the inside of the same foot.", "Zigzag to the end, then jog back and use the other foot."],
  ["Cut close to the cone, about half a metre away.", "Bend your knees as you cut, then push away.", "Keep the ball moving: no stopping at the cones."],
  ["DRI", "BC"], ["Dribbling", "Ball control", "Weak foot"],
  board([cone(-1, -1), cone(1, -4), cone(-1, -7), cone(1, -10), cone(-1, -13), cone(1, -16)], [you(0, 1.5)], [[0, 1.1]],
        [run((0, 1.5), (-0.5, -1), (0.5, -4), (-0.5, -7), (0.5, -10), (-0.5, -13), (0.5, -16), (0, -17))]),
  gear=["Ball", "6 cones"], space="18 m long", progression="Outside of the foot only, swapping feet at each cone.")
D("pull-back-turns", "Pull-Back Turns", "Dribbling", 2, 4, f"3 {X} 6 turns",
  "Put two cones 10 m apart.",
  ["Dribble toward the far cone.", "Halfway there, put your sole on the ball and pull it back.",
   "Turn your body the same way and dribble back to the start.", "Turn with the other foot next time."],
  ["Stop the ball with the sole, don't just tap it.", "Turn fast: hips first, then the ball.", "Speed up away from the turn."],
  ["DRI", "BC"], ["Dribbling", "1v1s", "Ball control"],
  board([cone(0, 0.8), cone(0, -10)], [you(0.4, 0)], [[0.4, -0.4]], [run((0.4, 0), (0.4, -5)), run((-0.4, -5), (-0.4, 0))]),
  gear=["Ball", "2 cones"], space="10 m", progression="Do a pull-back every 3 m, swapping feet each time.")
D("step-over-go", "Step-Over and Go", "Dribbling", 3, 5, f"3 {X} 4 runs",
  "Put a cone 8 m away as a defender.",
  ["Dribble at the cone at a jog.", "About a metre before it, step over the ball with your right foot as if going right.",
   "Push the ball the other way with the outside of your left foot.", "Speed past the cone and stop the ball 5 m beyond it. Swap sides each go."],
  ["Big shoulder drop on the step-over.", "Do the move a metre away, not right on top of the cone.", "Explode out of it: two fast touches."],
  ["DRI"], ["Dribbling", "1v1s"],
  board([cone(0, -8)], [you(0, 0.6)], [[0, 0.2]], [run((0, 0.6), (0, -6.8)), run((0, -6.8), (-1.4, -8.2), (-1.4, -13))]),
  gear=["Ball", "1 cone"], space="15 m", progression="Do two step-overs before you go.")
D("shoulder-drop", "Shoulder Drop", "Dribbling", 3, 5, f"3 {X} 4 runs",
  "Put a cone 8 m away as a defender.",
  ["Dribble at the cone at a jog.", "A metre before it, dip your shoulder and lean hard to one side without touching the ball.",
   "Push the ball the other way with the outside of your foot.", "Speed up past the cone. Swap sides each go."],
  ["The fake is all body: shoulder, head and hips.", "Step wide with the fake foot to make it look real.", "Change speed after the move."],
  ["DRI"], ["Dribbling", "1v1s"],
  board([cone(0, -8)], [you(0, 0.6)], [[0, 0.2]], [run((0, 0.6), (0, -6.8)), run((0, -6.8), (1.4, -8.2), (1.4, -13))]),
  gear=["Ball", "1 cone"], space="15 m", progression="Fake twice, then go.")
D("cruyff-lane", "Cruyff Turn Lane", "Dribbling", 3, 5, f"3 {X} 6 turns",
  "Put three cones in a line, 5 m apart.",
  ["Dribble from an end cone toward the middle one.", "At the middle cone, shape to pass: standing foot beside the ball.",
   "Instead, drag the ball behind your standing leg with the inside of your kicking foot.",
   "Turn, dribble back to the end cone, then do it from the other end."],
  ["Sell the fake pass: arm out, head down.", "Drag it with the inside of the foot, not the sole.", "Turn tight around the ball and push away fast."],
  ["DRI", "BC"], ["Dribbling", "1v1s", "Composure"],
  board([cone(0, 0.6), cone(0, -5), cone(0, -10)], [you(0.5, 0)], [[0.5, -0.4]], [run((0.5, 0), (0.5, -4.4)), run((-0.4, -4.4), (-0.4, 0))]),
  gear=["Ball", "3 cones"], space="10 m", progression="Do it at full speed, then with your weaker foot.")
D("funnel-dribble", "Funnel Dribble", "Dribbling", 3, 4, f"4 {X} 2 runs",
  "Make a funnel: two cones 6 m apart at the start, two 3 m apart halfway, and two 1 m apart 12 m away.",
  ["Dribble from the wide end toward the narrow end.", "Use bigger touches in the wide part.",
   "Make your touches smaller as the funnel gets narrow.", "Squeeze out through the narrow gate without touching a cone, then jog back."],
  ["Change the size of your touch as the space changes.", "Eyes up to see the gap.", "Go through the narrow gate at speed, don't stop."],
  ["DRI", "BC"], ["Dribbling", "Ball control", "Composure"],
  board([cone(-3, 0), cone(3, 0), cone(-1.5, -6), cone(1.5, -6), cone(-0.5, -12), cone(0.5, -12)], [you(0, 0.8)], [[0, 0.4]],
        [run((0, 0.8), (0, -13))]),
  gear=["Ball", "6 cones"], space="12 m long", progression="Weaker foot only through the narrow half.")
D("flip-flap", "Flip-Flap Steps", "Dribbling", 4, 5, f"3 {X} 8 each foot",
  "Stand with the ball in front of you and a cone 3 m ahead.",
  ["Push the ball out with the outside of your foot.", "Before it gets away, snap it back the other way with the inside of the same foot.",
   "Start slowly, walking, with a big gap between the two touches.", "Bring the two touches closer until they feel like one. Then do it at the cone."],
  ["Keep the foot near the ball: outside out, inside back.", "Your ankle does the work; keep the knee soft.", "Lean the way of the first touch to fool the defender."],
  ["DRI", "BC"], ["Dribbling", "1v1s"],
  board([cone(0, -3)], [you(0, 0.6)], [[0, 0.1]], [ball((0, 0.1), (0.6, -0.4), (-0.8, -1))]),
  gear=["Ball", "1 cone"], space="5 m", progression="Do it while dribbling at a jog.")
D("roulette-spin", "Roulette Spin", "Dribbling", 4, 5, f"3 {X} 6 spins",
  "Put a cone 6 m in front of you as a defender.",
  ["Dribble at the cone.", "Stop the ball with the sole of your right foot and spin so your back turns toward the cone.",
   "As you turn, drag the ball with the sole of your left foot so it comes with you.",
   "Finish facing forward again, past the cone. Spin the other way next time."],
  ["Keep your back between the cone and the ball as you spin.", "Two sole touches, one smooth turn.", "Stay low and finish moving forward."],
  ["DRI", "BC"], ["Dribbling", "1v1s", "Composure"],
  board([cone(0, -6)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -5)), run((0, -5), (0.9, -5.6), (0.9, -6.6), (0, -7.4), (0, -10))]),
  gear=["Ball", "1 cone"], space="10 m", progression="Do it at speed and finish with a pass against a wall.")
D("slow-quick-lanes", "Slow-Quick Lanes", "Dribbling", 4, 5, f"3 {X} 4 runs",
  "Mark a 30 m lane with cones every 10 m: three zones in a row.",
  ["Dribble through the first zone slowly, keeping the ball close.", "In the second zone, push the ball ahead and sprint with it.",
   "Slow right down in the last zone and stop the ball on the line.", "Walk back and go again."],
  ["The jump in speed is the skill.", "Bigger touches when you sprint, but never out of reach.", "Brake with small chopping steps."],
  ["DRI", "PHY"], ["Dribbling", "Speed", "Ball control"],
  board([cone(x, -z) for z in (0, 10, 20, 30) for x in (-1.5, 1.5)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -9.6)), run((0, -10.4), (0, -19.6)), run((0, -20.4), (0, -30))]),
  gear=["Ball", "8 cones"], space="30 m lane", progression="Change speed twice inside each zone.")
D("move-chain", "Move Chain", "Dribbling", 5, 6, f"4 {X} 2 runs",
  "Put four cones in a line, 5 m apart.",
  ["Dribble at full speed toward the first cone.",
   "Beat the first cone with a step-over, the second with an inside cut, the third with a Cruyff and the last with a roulette.",
   "Never stop the ball between moves.", "Jog back and do the moves in a new order."],
  ["Match speed: if it's slow, it won't work in a game.", "Get the ball back under control quickly after each move.", "Pick each move before you reach the cone."],
  ["DRI", "BC", "PHY"], ["Dribbling", "1v1s", "Composure"],
  board([cone(0, -5), cone(0, -10), cone(0, -15), cone(0, -20)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -4), (1, -5), (0, -6.4), (0, -9), (-1, -10), (0, -11.4), (0, -14), (1, -15), (0, -16.4), (0, -19),
             (-1, -20), (0, -21.4))]),
  gear=["Ball", "4 cones"], space="22 m", progression="Time each run and beat it without losing the ball.")

# ---- First touch
D("sole-trap", "Sole Trap", "First touch", 1, 4, f"3 {X} 12 passes",
  "Stand 4 m from a wall.",
  ["Pass the ball against the wall with the inside of your foot.", "As it comes back, lift your foot a little and put your sole on top of the ball.",
   "Stop it dead under your foot.", "Pass again. Swap feet every six passes."],
  ["Toes up, heel down: make a little roof over the ball.", "Meet the ball just in front of you.", "Don't stamp on it: press gently."],
  ["BC"], ["First touch", "Ball control"],
  board(wall(-4), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -3.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 5 m", progression="Pass harder so the trap is tougher.", tags=["touch"])
D("inside-cushion", "Inside Cushion", "First touch", 1, 4, f"3 {X} 10 each foot",
  "Stand in open space with the ball in your hands.",
  ["Toss the ball gently up in front of you.", "As it drops, meet it with the inside of your foot.",
   "Pull your foot back a little as it lands, so the ball dies at your feet.", "Pick it up and go again. Then swap feet."],
  ["Soft foot: like catching an egg.", "Turn your foot out so the inside faces the ball.", "Balance on the standing leg with a bent knee."],
  ["BC"], ["First touch", "Ball control", "Composure"], spot(),
  progression="Toss it higher, or let it bounce once first.", tags=["touch", "anywhere"])
D("drop-and-kill", "Drop and Kill", "First touch", 2, 4, f"3 {X} 10 drops",
  "Stand in open space with the ball in your hands.",
  ["Throw the ball up above your head.", "Watch it down and meet it with your laces just before it lands.",
   "Drop your foot with the ball so it stops right at your feet.", "Use the right foot five times, then the left."],
  ["Toes pointed a little, ankle relaxed.", "Move your feet to get under the ball early.", "Eyes on the ball until it's dead."],
  ["BC"], ["First touch", "Ball control"], spot(),
  progression="Throw it higher, then try it while walking.", tags=["touch", "anywhere"])
D("thigh-control", "Thigh Control", "First touch", 2, 4, f"3 {X} 10 each leg",
  "Stand in open space with the ball in your hands.",
  ["Throw the ball up to about head height.", "Lift your thigh to meet it and let the thigh drop as the ball lands.",
   "The ball should fall softly in front of your feet.", "Stop it with your sole or the inside of your foot."],
  ["Thigh flat, knee up at hip height.", "Give with the leg to take the pace off.", "Two touches: thigh, then foot."],
  ["BC"], ["First touch", "Ball control"], spot(),
  progression="Control on the thigh, then pass it against a wall.", tags=["touch"])
D("back-foot-receive", "Back Foot Receive", "First touch", 2, 5, f"3 {X} 10 passes",
  "Stand 5 m from a wall. Put two cones 2 m apart as a gate, 3 m to your right.",
  ["Stand side-on to the wall with the gate on your right.", "Pass against the wall with your left foot.",
   "Let the rebound run across your body and touch it with your right foot, the one further from the wall.",
   "Your touch goes through the gate. Dribble back and go again, then swap sides."],
  ["Side-on lets you see more of the pitch.", "Receive with the back foot to play forward faster.", "Touch toward the gate, not under your body."],
  ["BC", "PAS"], ["First touch", "Vision", "Composure"],
  board(wall(-5) + [cone(3, -1), cone(3, 1)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -4.8), both=True), ball((0.3, 0), (3.8, 0))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 6 m", progression="One touch through the gate, the next back against the wall.")
D("weak-foot-receive", "Weak Foot Receive", "First touch", 2, 4, f"3 {X} 12 passes",
  "Stand 4 m from a wall. Use your weaker foot for everything.",
  ["Pass against the wall with your weaker foot.", "Control the rebound with the inside of the same foot.",
   "Next time control it with the sole, then with the outside.", "Keep going round the three touches."],
  ["Relax: a stiff foot makes the ball bounce off.", "Get your body behind the ball.", "Slow and clean before fast."],
  ["BC", "PAS"], ["Weak foot", "First touch"],
  board(wall(-4), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -3.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 5 m", progression="Step back to 7 m and pass harder.", tags=["both feet"])
D("chest-control", "Chest Control", "First touch", 3, 5, f"3 {X} 10 throws",
  "Stand in open space with the ball in your hands.",
  ["Throw the ball up so it drops toward your chest.", "Lean back a little and push your chest out to meet it.",
   "Let your chest sink back as the ball lands so it falls to your feet.", "Control it with your foot before it bounces away."],
  ["Arms wide for balance, never touching the ball.", "Bend your knees to cushion it.", "Chest, then foot: the second touch matters too."],
  ["BC"], ["First touch", "Ball control", "Composure"], spot(),
  progression="Turn your chest as the ball lands, so it drops to one side.", tags=["touch"])
D("outside-foot-touch", "Outside Foot Touch", "First touch", 3, 5, f"3 {X} 10 passes",
  "Stand 4 m from a wall with a cone 2 m to each side of you.",
  ["Pass against the wall.", "As the ball comes back, touch it sideways with the outside of your foot.",
   "Follow it and pass again from beside the cone.", "Next time go the other way with the outside of the other foot."],
  ["Turn your toes in so the outside of the foot faces the ball.", "The touch moves the ball one step, no more.", "Push off quickly after the touch."],
  ["BC", "DRI"], ["First touch", "Ball control", "Weak foot"],
  board(wall(-4) + [cone(-2, 0), cone(2, 0)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -3.8), both=True), ball((0.2, -0.2), (1.6, -0.5))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 5 m", progression="Pass with one foot and touch with the outside of the other.")
D("two-gate-touch", "Two-Gate Touch", "First touch", 3, 5, f"3 {X} 12 passes",
  "Stand 5 m from a wall. Make a small gate of two cones 2 m to your left, and another 2 m to your right.",
  ["Pass against the wall.", "While the ball travels, pick a gate and say it out loud.",
   "Take your first touch through that gate.", "Come back to the middle and go again. Pick a different gate each time."],
  ["Decide before the ball arrives.", "Touch with the foot nearest the gate.", "A good touch sets up your next pass."],
  ["BC", "PAS"], ["First touch", "Vision"],
  board(wall(-5) + [cone(-2.2, -0.6), cone(-2.2, 0.6), cone(2.2, -0.6), cone(2.2, 0.6)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -4.8), both=True), ball((-0.2, 0), (-2.8, 0))]),
  gear=["Ball", "Wall", "4 cones"], space="A wall and 6 m", progression="Touch through the gate, then pass straight back to the wall.")
D("high-ball-kill", "High Ball Kill", "First touch", 4, 5, f"3 {X} 8 kicks",
  "Stand in open space with the ball at your feet.",
  ["Kick the ball straight up as high as you can.", "Move under it fast and watch it all the way down.",
   "Kill it with your laces, thigh or the inside of your foot.", "It should be dead within one step of you."],
  ["Move early: be waiting for the ball.", "Pick the body part before it lands.", "Cushion by moving with the ball, not against it."],
  ["BC"], ["First touch", "Ball control", "Composure"],
  board([cone(-1.5, -1.5), cone(1.5, -1.5), cone(-1.5, 1.5), cone(1.5, 1.5)], [you(0, 0.6)], [[0.6, -0.6]], [run((0, 0.6), (0.5, -0.3))]),
  space="5 m square", progression="Kill it with your weaker foot only.", tags=["touch", "anywhere"])
D("turn-on-touch", "Turn on the Touch", "First touch", 4, 5, f"3 {X} 10 passes",
  "Stand 4 m from a wall with a cone 4 m behind you.",
  ["Pass against the wall.", "As it comes back, open your hips and let the ball run across you.",
   "Use one touch to turn all the way round toward the cone.", "Dribble round the cone and come back to pass again."],
  ["Get your body shape ready before the ball arrives.", "Touch with the inside of your back foot to turn.", "One touch to turn, the next to move away."],
  ["BC", "DRI"], ["First touch", "Composure", "Dribbling"],
  board(wall(-4) + [cone(0, 4)], [you(0, 0.4)], [[0, 0]],
        [ball((0, 0), (0, -3.8), both=True), run((0.3, 0.5), (0.6, 3.4), (0, 4.6), (-0.6, 3.4))]),
  gear=["Ball", "Wall", "1 cone"], space="A wall and 8 m", progression="Turn the other way, with the other foot.")
D("running-touch", "Running Touch", "First touch", 5, 6, f"3 {X} 4 runs",
  "Mark a 15 m lane along a wall, with a cone at each end.",
  ["Jog along the wall with the ball.", "Pass it against the wall a little ahead of you.",
   "Keep running and take the rebound in your stride, without slowing down.", "Repeat all the way down the lane, then come back the other way."],
  ["Pass ahead of you, not at you.", "Touch the ball forward, into your running path.", "Keep your speed up: the touch should help you go faster."],
  ["BC", "PAS", "PHY"], ["First touch", "Passing", "Speed"],
  board([cone(x, -3) for x in range(-7, 8)] + [cone(-7.5, 0.8), cone(7.5, 0.8)], [you(-7, 0.4, PI / 2)], [[-6.5, 0]],
        [run((-7, 0.8), (7, 0.8)), ball((-6, 0), (-4.5, -2.8), (-3, 0)), ball((-1.5, 0), (0, -2.8), (1.5, 0)), ball((3, 0), (4.5, -2.8), (6, 0))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 15 m", progression="Go at a sprint, and use your weaker foot on the way back.")

# ---- Passing
D("short-gate-pass", "Short Gate Pass", "Passing", 1, 4, f"3 {X} 10 passes",
  "Put two cones 1 m apart as a gate. Stand 5 m from it with the ball.",
  ["Pass through the gate with the inside of your foot.", "Jog after it, stop it, and turn round.",
   "Pass back through the gate from the other side.", "Use your right foot one way and your left foot the other."],
  ["Standing foot beside the ball, pointing at the gate.", "Lock your ankle and push through the middle of the ball.", "Keep the pass on the ground."],
  ["PAS"], ["Passing", "Weak foot"],
  board([cone(-0.5, -5), cone(0.5, -5)], [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -10))]),
  gear=["Ball", "2 cones"], space="12 m", progression="Step back to 8 m, or make the gate half as wide.", tags=["both feet"])
D("distance-ladder", "Distance Ladder", "Passing", 1, 5, f"3 {X} 8 passes",
  "Put a cone at 5 m, 10 m, 15 m and 20 m in a line in front of you.",
  ["Pass the ball so it stops next to the 5 m cone.", "Fetch it, come back, and try to stop the next one at the 10 m cone.",
   "Work up to 20 m, then back down.", "Score a point for every ball that stops within a big step of its cone."],
  ["How hard you pass matters as much as the aim.", "A longer pass needs a longer follow-through, not a wild swing.", "Watch how far each ball runs and adjust."],
  ["PAS"], ["Passing", "Long balls"],
  board([cone(0, -5), cone(0, -10), cone(0, -15), cone(0, -20)], [you(0.6, 0.6)], [[0, 0]], [ball((0, 0), (0.4, -9.6))]),
  gear=["Ball", "4 cones"], space="22 m", progression="Do the same with your weaker foot.")
D("angled-wall-passes", "Angled Wall Passes", "Passing", 2, 5, f"3 {X} 12 passes",
  "Stand 5 m from a wall, off to one side, with a cone 4 m along to the other side.",
  ["Pass against the wall at an angle so the ball comes back to the cone.", "Run to the cone and meet the ball there.",
   "Control it and pass at an angle back to where you started.", "Run back and meet it again."],
  ["Aim at the spot on the wall halfway between you and the cone.", "Open your body toward where the ball will come back.", "Get there before the ball does."],
  ["PAS", "BC"], ["Passing", "First touch", "Positioning"],
  board(wall(-5, 3) + [cone(2, 0.4)], [you(-2, 0.4)], [[-2, 0]], [ball((-2, 0), (0, -4.8), (2, 0)), run((-2, 0.8), (1.6, 0.8))]),
  gear=["Ball", "Wall", "1 cone"], space="A wall and 6 m", progression="Pass first time when you arrive.")
D("pass-and-move", "Pass and Move", "Passing", 2, 5, f"3 {X} 45 s",
  "Stand 4 m from a wall with three cones in an arc behind you, 2 m apart.",
  ["Pass against the wall from the middle cone.", "Straight away, move to a different cone.",
   "Receive the rebound there and pass again.", "Never pass from the same cone twice in a row."],
  ["Pass, then move: never stand and watch.", "Small quick steps to get there.", "Open up toward the wall before the ball arrives."],
  ["PAS", "PHY"], ["Passing", "Positioning", "Stamina"],
  board(wall(-4, 3) + [cone(-2, 0.4), cone(0, 1), cone(2, 0.4)], [you(0, 0.6)], [[0, 0.2]],
        [ball((0, 0.2), (0, -3.8), (1.8, 0)), run((0, 0.6), (1.7, 0.2))]),
  gear=["Ball", "Wall", "3 cones"], space="A wall and 5 m", progression="Two touches only, then one touch.")
D("left-right-wall", "Left-Right Wall Passes", "Passing", 2, 4, f"3 {X} 20 passes",
  "Stand 3 m from a wall.",
  ["Pass against the wall with your right foot.", "Control the rebound with your left foot, across your body.",
   "Pass with the left this time, and control with the right.", "Keep swapping. Count how many you get in a row."],
  ["Control the ball into the space in front of your passing foot.", "Same pace off both feet.", "Stay on your toes."],
  ["PAS", "BC"], ["Passing", "Weak foot", "First touch"],
  board(wall(-3), [you(0, 0.4)], [[0, 0]], [ball((-0.4, 0), (0, -2.8), (0.4, 0))]),
  gear=["Ball", "Wall"], space="A wall and 4 m", progression="Step back to 6 m and pass harder.", tags=["both feet"])
D("driven-pass", "Driven Pass", "Passing", 3, 5, f"3 {X} 8 passes",
  "Put two cones 2 m apart as a gate, 15 m away.",
  ["Take two steps back from the ball and one to the side.", "Strike through the middle of the ball with your laces, toes down.",
   "Keep it low and fast: no higher than your knee.", "Fetch it and go again from the other side."],
  ["Head over the ball keeps it low.", "Short, punchy follow-through.", "Hit the middle of the ball, not underneath it."],
  ["PAS", "SHO"], ["Passing", "Long balls"],
  board([cone(-1, -15), cone(1, -15)], [you(0.6, 0.8)], [[0, 0]], [run((0.6, 0.8), (0.2, 0.2)), ball((0, 0), (0, -15))]),
  gear=["Ball", "2 cones"], space="20 m", progression="Make the gate 1 m wide, or use your weaker foot.")
D("chip-pass", "Chip Pass", "Passing", 3, 5, f"3 {X} 8 chips",
  "Put a cone 5 m in front of you as a defender. Mark a 3 m square with four cones 15 m away.",
  ["Stand the ball still in front of you.", "Stab down into the bottom of the ball, with very little follow-through.",
   "Make it lift over the defender cone.", "Land it in the square. Fetch it and go again."],
  ["Lean back a little as you strike.", "Hit right under the ball so it spins backwards.", "Short, sharp kick: don't swing through."],
  ["PAS"], ["Passing", "Long balls", "Vision"],
  board([cone(0, -5), cone(-1.5, -13.5), cone(1.5, -13.5), cone(-1.5, -16.5), cone(1.5, -16.5)], [you(0.5, 0.6)], [[0, 0]],
        [ball((0, 0), (0, -15))]),
  gear=["Ball", "5 cones"], space="20 m", progression="Chip a moving ball: roll it forward first.")
D("wall-one-two", "Wall One-Two", "Passing", 3, 5, f"3 {X} 6 runs",
  "Find a long wall. Stand 3 m from it, with a cone 5 m ahead of you as a defender.",
  ["Dribble toward the defender cone.", "Two steps before it, pass against the wall so the ball comes back behind the cone.",
   "Sprint past the other side of the cone.", "Collect the rebound and dribble on. Turn round and come back the other way."],
  ["Pass early, before the defender can step in.", "Sprint as soon as the ball leaves your foot.", "Angle the pass so it comes back into your path."],
  ["PAS", "DRI"], ["Passing", "1v1s", "Vision"],
  board([cone(-3, -z) for z in range(0, 11)] + [cone(0, -5)], [you(0, 0.6)], [[0, 0.2]],
        [run((0, 0.6), (0, -3)), ball((0, -3.2), (-2.8, -5), (-0.4, -7)), run((0.3, -3.2), (1, -5), (-0.2, -7))]),
  gear=["Ball", "Wall", "1 cone"], space="A wall and 10 m", progression="Do it at full speed with a first-time pass.")
D("outside-foot-pass", "Outside of the Foot", "Passing", 4, 5, f"3 {X} 10 passes",
  "Put two cones 1.5 m apart as a gate, 10 m away and a little to your right.",
  ["Stand with the ball a little left of the line to the gate.", "Strike it with the outside of your right foot, toes pointing down and in.",
   "Let the ball curve out toward the gate.", "Fetch it and go again. Then use your left foot to a gate on the left."],
  ["Flick the ankle out as you strike.", "Short swing: this is a pass, not a shot.", "Strike the inside half of the ball to make it bend out."],
  ["PAS"], ["Passing", "Vision", "Weak foot"],
  board([cone(2.5, -10), cone(4, -10)], [you(-0.6, 0.6)], [[0, 0]], [ball((0, 0), (1.2, -5), (3.2, -10))]),
  gear=["Ball", "2 cones"], space="12 m", progression="Pass while you jog, without stopping the ball first.")
D("switch-play", "Switch of Play", "Passing", 4, 6, f"3 {X} 6 passes",
  "Mark a 5 m square with four cones about 30 m away, out to one side.",
  ["Dribble forward a few steps, then look up at the square.", "Strike a long pass with the inside of your laces, across your body.",
   "Try to land it in the square before it bounces.", "Fetch it, go back, and switch it from the other side."],
  ["Look up before you strike: know where the square is.", "Come in at an angle and lean back a little.", "Follow through high toward the target."],
  ["PAS"], ["Long balls", "Passing", "Vision"],
  board([cone(12, -22), cone(17, -22), cone(12, -27), cone(17, -27)], [you(-1, 1.5)], [[-0.6, 0.8]],
        [run((-1, 1.5), (-0.2, 0.2)), ball((0, 0), (14.5, -24.5))]),
  gear=["Ball", "4 cones"], space="Half a pitch", progression="Switch it with your weaker foot.")
D("bent-pass", "Bend It Round a Cone", "Passing", 4, 5, f"3 {X} 8 passes",
  "Put a cone 6 m ahead as a defender, and a gate of two cones 1.5 m apart 12 m away, straight behind it.",
  ["Line up so the defender cone blocks the straight path to the gate.", "Strike across the ball with the inside of your foot.",
   "Bend it round the cone and back in through the gate.", "Go round the left side, then the right."],
  ["Hit the outside half of the ball to make it curl.", "Wrap your foot round the ball and follow through across your body.", "Start the ball outside the cone, not at it."],
  ["PAS"], ["Passing", "Crossing", "Vision"],
  board([cone(0, -6), cone(-0.75, -12), cone(0.75, -12)], [you(-0.5, 0.6)], [[0, 0]], [ball((0, 0), (-1.6, -6), (0, -12))]),
  gear=["Ball", "3 cones"], space="15 m", progression="Bend it with your weaker foot.")
D("first-time-angles", "First-Time Angles", "Passing", 5, 5, f"4 {X} 30 s",
  "Stand 3 m from a wall, between two cones 3 m apart.",
  ["Pass against the wall.", "Shuffle sideways toward one cone as the ball comes back.",
   "Pass it first time back at the wall, angled so it returns toward the other cone.", "Shuffle across and do it again. Keep it going for the whole set."],
  ["Feet set and balanced at the moment you pass.", "Angle the pass with your body, not just your foot.", "Every pass first time: no stopping the ball."],
  ["PAS", "BC", "PHY"], ["Passing", "First touch", "Weak foot"],
  board(wall(-3, 3) + [cone(-1.5, 0.4), cone(1.5, 0.4)], [you(-1, 0.4)], [[-1, 0]],
        [ball((-1, 0), (0, -2.8), (1, 0)), run((-1, 0.9), (1, 0.9), both=True)]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 4 m", progression="Move the cones 5 m apart and keep it first time.")

# ---- Shooting
D("side-foot-finish", "Side-Foot Finish", "Shooting", 1, 5, f"3 {X} 8 shots",
  "Put the ball 8 m from a goal or a target on a wall.",
  ["Pick a corner before you start.", "Take two steps back and run up slowly.",
   "Pass the ball into the corner with the inside of your foot.", "Fetch it and go for the other corner."],
  ["From close in, placement beats power.", "Standing foot points at the corner you want.", "Keep your head down until the ball has gone."],
  ["SHO"], ["Finishing", "Shooting", "Composure"],
  board([goal(0, -8)], [you(0.6, 1)], [[0, 0]], [run((0.6, 1), (0.2, 0.3)), ball((0, 0), (-3, -8))]),
  gear=["Ball", "Goal or wall target"], space="10 m and a goal", progression="Use your weaker foot.")
D("corner-targets", "Corner Targets", "Shooting", 2, 6, f"3 {X} 8 shots",
  "Put a cone on the goal line 1 m inside each post. Put the ball 12 m out.",
  ["Aim between a post and its cone.", "Strike with your laces or the inside of your foot.",
   "Score 2 points for a goal in the target, 1 for any other goal.", "Switch corners each shot and try to beat your score each set."],
  ["Pick the corner before you run up.", "Low corners are the hardest for a keeper.", "Same routine every shot."],
  ["SHO"], ["Shooting", "Finishing"],
  board([goal(0, -12), cone(-2.66, -12), cone(2.66, -12)], [you(0.6, 1)], [[0, 0]], [run((0.6, 1), (0.2, 0.3)), ball((0, 0), (3.2, -12))]),
  gear=["Ball", "Goal", "2 cones"], space="15 m and a goal", progression="Shoot from 16 m.")
D("rolling-ball-strike", "Moving Ball Strike", "Shooting", 2, 6, f"3 {X} 6 shots",
  "Start 18 m from a goal with the ball at your feet.",
  ["Roll the ball a couple of metres forward with your sole.", "Run onto it and shoot without stopping it.",
   "Strike with your laces through the middle of the ball.", "Fetch it and go again."],
  ["Time your steps so your standing foot lands beside the ball.", "Keep your body over the ball as it moves.", "Look at the ball, not the goal, as you strike."],
  ["SHO"], ["Shooting", "Finishing"],
  board([goal(0, -16)], [you(0.5, 3)], [[0, 2.6]], [ball((0, 2.6), (0, 0.4)), ball((0, 0.2), (-2.5, -16))]),
  gear=["Ball", "Goal or wall target"], space="20 m and a goal", progression="Roll it to the side and strike across it.")
D("weak-foot-finish", "Weak Foot Finishing", "Shooting", 2, 5, f"3 {X} 8 shots",
  "Put the ball 10 m from goal. Use your weaker foot only.",
  ["Start with side-foot finishes into the corners.", "When five go in, switch to laces strikes.",
   "Then take one touch out of your feet and shoot.", "Keep every shot on target before you add power."],
  ["Same technique as your strong foot, just slower at first.", "Plant your standing foot close to the ball.", "Accuracy first, power later."],
  ["SHO"], ["Weak foot", "Finishing", "Shooting"],
  board([goal(0, -10)], [you(-0.6, 1)], [[0, 0]], [run((-0.6, 1), (-0.2, 0.3)), ball((0, 0), (2.8, -10))]),
  gear=["Ball", "Goal or wall target"], space="12 m and a goal", progression="Shoot from the edge of the box.", tags=["both feet"])
D("curl-far-post", "Curl to the Far Post", "Shooting", 3, 6, f"3 {X} 6 shots",
  "Put the ball 16 m out, in line with the left post.",
  ["Run up at a slight angle.", "Strike the outside half of the ball with the inside of your right foot.",
   "Start it wide of the far post and let it bend back in.", "Then move to the right side and curl it with your left foot."],
  ["Wrap your foot round the ball and follow through across your body.", "Lean back less than for a pass: keep it under the bar.", "Aim outside the post: the curl brings it in."],
  ["SHO"], ["Shooting", "Finishing"],
  board([goal(0, -16)], [you(-4.4, 1)], [[-3.66, 0]], [ball((-3.66, 0), (1.5, -9), (3, -16))]),
  gear=["Ball", "Goal or wall target"], space="20 m and a goal", progression="Take a touch inside first, then curl it.")
D("turn-and-shoot", "Turn and Shoot", "Shooting", 3, 6, f"3 {X} 6 shots",
  "Stand 14 m from goal with your back to it and the ball at your feet. Put a cone right behind you as a defender.",
  ["Drag the ball to one side of the cone with your sole.", "Turn with it so you face the goal.",
   "Shoot with your next touch.", "Turn the other way next time."],
  ["Check over your shoulder before you turn.", "Take the ball away from the cone as you turn.", "Shoot early, before a defender could get back."],
  ["SHO", "DRI"], ["Finishing", "Shooting", "Composure"],
  board([goal(0, -14), cone(0, -0.9)], [you(0, 0, 0)], [[0, 0.4]], [run((0, 0.2), (1.2, -0.6), (1.4, -1.6)), ball((1.4, -1.8), (-2.6, -14))]),
  gear=["Ball", "Goal or wall target", "1 cone"], space="16 m and a goal", progression="Turn and shoot with only two touches.")
D("slalom-and-shoot", "Slalom and Shoot", "Shooting", 3, 6, f"3 {X} 4 shots",
  "Put four cones in a line, 1.5 m apart, with the last one 16 m from goal.",
  ["Dribble in and out of the cones.", "As you leave the last cone, set the ball out in front with one touch.",
   "Shoot at a corner.", "Jog back and go again."],
  ["Head up after the last cone to find the target.", "One set-up touch, then shoot.", "Keep your speed going into the shot."],
  ["SHO", "DRI"], ["Finishing", "Dribbling", "Shooting"],
  board([goal(0, -20.5), cone(0, 0), cone(0, -1.5), cone(0, -3), cone(0, -4.5)], [you(0, 1.5)], [[0, 1.1]],
        [run((0, 1.5), (0.5, 0), (-0.5, -1.5), (0.5, -3), (-0.5, -4.5), (0, -5.8)), ball((0, -6), (2.6, -20.5))]),
  gear=["Ball", "Goal or wall target", "4 cones"], space="25 m and a goal", progression="Shoot with the foot you didn't use last time.")
D("tight-angle-finish", "Tight Angle Finish", "Shooting", 3, 6, f"3 {X} 6 shots",
  "Put a cone 8 m out from the goal line and 6 m wide of a post.",
  ["Dribble from the cone toward the goal.", "When you're about 6 m out, look up at the near post.",
   "Shoot low across the goal toward the far side.", "Go from the other side next time."],
  ["From a tight angle, across the keeper is the best bet.", "Keep it low so a touch off anyone can still go in.", "Shoot before you run out of angle."],
  ["SHO"], ["Finishing", "Shooting", "Composure"],
  board([goal(0, -8), cone(-9.5, 0)], [you(-9.5, 0.6)], [[-9.1, 0.2]], [run((-9.5, 0.6), (-6, -4.5)), ball((-6, -4.7), (2.8, -8))]),
  gear=["Ball", "Goal", "1 cone"], space="The box and a goal", progression="Finish with the foot further from the goal.")
D("drop-volley", "Drop Volley", "Shooting", 4, 6, f"3 {X} 8 volleys",
  "Stand 12 m from a goal or a big wall target with the ball in your hands.",
  ["Drop the ball in front of your kicking foot.", "Before it bounces, strike it with your laces.",
   "Keep your knee over the ball so the shot stays low.", "Fetch it and go again. Swap feet halfway."],
  ["Toes pointed down, ankle locked.", "Watch the ball onto your foot.", "Short swing: a clean contact beats a big kick."],
  ["SHO", "BC"], ["Shooting", "Finishing", "Composure"],
  board([goal(0, -12)], [you(0, 0.4)], [[0, 0]], [ball((0, 0), (-2, -12))]),
  gear=["Ball", "Goal or wall target"], space="15 m and a goal", progression="Toss it up higher so it drops at an angle.")
D("half-volley", "Half-Volley", "Shooting", 4, 6, f"3 {X} 8 shots",
  "Stand 14 m from goal with the ball in your hands.",
  ["Toss the ball a step in front of you.", "Let it bounce once.", "Strike it with your laces just as it comes up off the ground.", "Swap feet halfway."],
  ["Strike at the moment it leaves the ground.", "Knee over the ball keeps it down.", "Lean forward, not back."],
  ["SHO"], ["Shooting", "Finishing"],
  board([goal(0, -14)], [you(0, 0.6)], [[0, -0.4]], [ball((0, -0.4), (2.4, -14))]),
  gear=["Ball", "Goal or wall target"], space="16 m and a goal", progression="Toss it to one side so you have to move to it.")
D("chip-finish", "Chip Finish", "Shooting", 4, 6, f"3 {X} 6 shots",
  "Put a cone 3 m out from the middle of the goal as the keeper. Start 16 m out.",
  ["Dribble at the keeper cone.", "About 8 m out, look up as if the keeper is rushing off the line.",
   "Stab under the ball to lift it over the cone and under the bar.", "Fetch it and go again."],
  ["Lean back a little and hit right under the ball.", "Short, sharp contact: no big follow-through.", "Chip only when the keeper is off the line."],
  ["SHO"], ["Finishing", "Composure"],
  board([goal(0, -16), cone(0, -13)], [you(0, 0.6)], [[0, 0.2]], [run((0, 0.6), (0, -7.4)), ball((0, -7.8), (0, -16))]),
  gear=["Ball", "Goal", "1 cone"], space="20 m and a goal", progression="Chip it after one touch out of your feet.")
D("knock-and-finish", "Knock and Finish", "Shooting", 5, 6, f"4 {X} 4 shots",
  "Start 22 m from goal with the ball.",
  ["Knock the ball 5 m ahead of you.", "Sprint after it.", "Shoot first time, without a controlling touch.",
   "Jog back. Knock it out to the left, then the right, so you shoot on the move from new angles."],
  ["Knock it far enough to run onto, not so far it stops dead.", "Shorten your last steps to set your feet.", "Pick your corner while you're running."],
  ["SHO", "PHY"], ["Finishing", "Shooting", "Speed"],
  board([goal(0, -22)], [you(0, 0.6)], [[0, 0.2]], [ball((0, 0.2), (0, -5)), run((0.6, 0.6), (0.6, -5)), ball((0, -5.2), (-2.6, -22))]),
  gear=["Ball", "Goal or wall target"], space="25 m and a goal", progression="Finish with your weaker foot every other go.")

# ---- Defending
D("defensive-stance", "Defensive Stance Holds", "Defending", 1, 3, f"3 {X} 30 s",
  "Mark a 3 m square with four cones. No ball needed.",
  ["Get into your defending stance: side-on, knees bent, weight on the balls of your feet.", "Hold it for five seconds.",
   "Do three quick shuffles to one side, then hold again.", "Then three to the other side. Keep going for the set."],
  ["One foot a little in front of the other, never square.", "Back flat, chest up, eyes forward.", "Arms out low for balance."],
  ["DEF", "PHY"], ["Defending", "Positioning"],
  board([cone(-1.5, -1), cone(1.5, -1), cone(-1.5, 1), cone(1.5, 1)], [you(0, 0)], [], [run((-1, 0.5), (1, 0.5), both=True)]),
  ball=False, gear=["4 cones"], space="3 m square", progression="Hold the stance for 10 seconds and shuffle faster.", tags=["warm-up"])
D("poke-tackle", "Poke Tackle", "Defending", 2, 4, f"3 {X} 8 each foot",
  "Put two cones 4 m ahead of you, 4 m apart, as the attacker's path. Start with the ball at your feet.",
  ["Nudge the ball 2 m ahead of you, as if an attacker has taken a touch.", "Close in on it quickly, then slow down into your stance.",
   "Jab your front foot out and poke the ball away to the side.", "Get back into your stance at once. Swap your front foot each go."],
  ["Short, quick jab with your front foot.", "Get straight back into your stance after it.", "Don't dive in: stay on your feet."],
  ["DEF"], ["Defending", "1v1s"],
  board([cone(-2, -4), cone(2, -4)], [you(0, 0.6)], [[0, -2]], [run((0, 0.6), (0, -1.4)), ball((0, -2.2), (1.8, -3))]),
  gear=["Ball", "2 cones"], space="5 m", progression="Poke it with the foot nearer the side you want to send it.")
D("block-tackle-shape", "Block Tackle Shape", "Defending", 2, 4, f"3 {X} 8 each foot",
  "Put the ball against the bottom of a wall.",
  ["Stand a step from the ball, side-on.", "Step in and put the inside of your foot firmly against the middle of the ball.",
   "Push through it with your weight behind the foot, as if a player is pushing back.", "Hold for two seconds, step out and repeat. Swap feet."],
  ["Lock your ankle and turn your foot out.", "Knee over the ball, body weight forward.", "Meet the middle of the ball, never the top."],
  ["DEF", "PHY"], ["Defending", "Strength"],
  board(wall(-1), [you(0, 1)], [[0, -0.7]], [run((0, 1), (0, -0.2))]),
  gear=["Ball", "Wall"], space="A wall and 2 m", progression="Step in from two steps away, then from a jog.")
D("drop-step-turns", "Drop Step Turns", "Defending", 2, 4, f"3 {X} 6 turns",
  "Put two cones 10 m apart. No ball needed.",
  ["Face the first cone in your stance.", "Shuffle back a few steps.",
   "Open your hips to one side with a drop step and run toward the far cone, as if racing an attacker.", "Walk back. Open the other way next time."],
  ["Turn your hips first, then your feet.", "Never cross your feet while you shuffle.", "Stay low as you turn so you don't lose speed."],
  ["DEF", "PHY"], ["Defending", "Speed", "Positioning"],
  board([cone(0, -1), cone(0, 10)], [you(0, 0)], [], [run((0, 0.3), (0, 2)), run((0.2, 2.2), (1.2, 3.4), (0.6, 9.4))]),
  ball=False, gear=["2 cones"], space="12 m", progression="Have someone point the way you must open.")
D("zigzag-jockey", "Zigzag Jockey", "Defending", 3, 5, f"3 {X} 2 runs",
  "Put six cones in a zigzag, each 3 m further back and 3 m to the side of the last. No ball needed.",
  ["Start at the first cone in your stance, facing up the zigzag.", "Shuffle backwards at an angle to the next cone.",
   "At each cone, switch your front foot and go the other way.", "Stay low all the way to the last cone, then walk back."],
  ["Side-on the whole time: never turn your back.", "Small steps, feet never cross.", "Switch feet quickly at each cone."],
  ["DEF", "PHY"], ["Defending", "1v1s", "Positioning"],
  board([cone(0, 0), cone(3, 3), cone(0, 6), cone(3, 9), cone(0, 12), cone(3, 15)], [you(0, -0.6)], [],
        [run((0, -0.3), (2.6, 3), (0.4, 6), (2.6, 9), (0.4, 12), (2.6, 15))]),
  ball=False, gear=["6 cones"], space="16 m long", progression="At the last cone, sprint forward 3 m as if blocking a shot.")
D("show-outside", "Show Them Outside", "Defending", 3, 5, f"3 {X} 5 runs",
  "Put a cone 10 m away as the attacker, and a line of three cones beyond it, off to one side, as the touchline. No ball needed.",
  ["Sprint toward the attacker cone, but curve your run so you come in from the inside.",
   "Slow down two steps away and get side-on, showing the attacker toward the touchline.",
   "Shuffle sideways toward the touchline as if the attacker is running there.", "Walk back and go again."],
  ["Curved run: block the way to goal first.", "Your stance points the attacker the way you want them to go.", "Stay an arm's length away: close but not touching."],
  ["DEF"], ["Defending", "Positioning", "1v1s"],
  board([cone(0, -10), cone(5, -8), cone(5, -11), cone(5, -14)], [you(0, 0)], [],
        [run((0, 0), (-1.6, -5), (-0.8, -8.8)), run((-0.6, -9.2), (3.4, -10.6))]),
  ball=False, gear=["4 cones"], space="15 m", progression="Start facing away, turn on a count of three, then go.")
D("clearances", "Clearances", "Defending", 3, 5, f"3 {X} 8 clears",
  "Stand in open space with the ball in your hands. Mark a target zone with four cones about 20 m away, out to one side.",
  ["Throw the ball up in front of you.", "As it drops, kick it high and far with your laces toward the target zone.",
   "Clear it before it bounces if you can.", "Fetch it and go again. Swap feet halfway."],
  ["High and wide: get it away from the middle.", "Get your body behind the ball.", "Lean back a little for height."],
  ["DEF", "PAS"], ["Defending", "Long balls"],
  board([cone(10, -17), cone(14, -17), cone(10, -21), cone(14, -21)], [you(0, 0.4)], [[0, 0]], [ball((0, 0), (12, -19))]),
  gear=["Ball", "4 cones"], space="25 m", progression="Clear a bouncing ball, or use your weaker foot.")
D("intercept-step", "Intercept Step", "Defending", 4, 5, f"3 {X} 10 passes",
  "Stand 4 m from a wall, with a cone 4 m to your side.",
  ["Pass against the wall at an angle so the ball comes back toward the cone.", "As soon as it leaves the wall, step across into its path.",
   "Cut it off before it reaches the cone and take it away.", "Go the other way next time."],
  ["Read where the ball is going, then move.", "Step across with the foot nearer the ball's path.", "Win it and take it away with your first touch."],
  ["DEF", "BC"], ["Defending", "Positioning", "First touch"],
  board(wall(-4, 3) + [cone(3, 0.4)], [you(-1, 0.4)], [[-1, 0]], [ball((-1, 0), (0.5, -3.8), (2.6, 0)), run((-1, 0.4), (1.8, -0.6))]),
  gear=["Ball", "Wall", "1 cone"], space="A wall and 6 m", progression="Pass harder so you have less time.")
D("chase-down", "Chase Down", "Defending", 4, 5, f"3 {X} 4 runs",
  "Put two cones 25 m away as an end line.",
  ["Knock the ball hard toward the end line, as if an attacker has gone past you.", "Count one, then sprint after it.",
   "Get your body between the ball and the end line before it crosses.", "Shield it, turn and dribble back."],
  ["Run to where the ball will be, not where it is.", "Get goal-side first, then win the ball.", "Use your arm and body to shield once you're there."],
  ["DEF", "PHY"], ["Defending", "Speed", "Strength"],
  board([cone(-3, -25), cone(3, -25)], [you(0, 0.6)], [[0, 0]], [ball((0, 0), (0.6, -18)), run((0.8, 0.6), (-0.6, -20))]),
  gear=["Ball", "2 cones"], space="30 m", progression="Count two before you go.")
D("footwork-box", "Footwork Box", "Defending", 5, 5, f"4 {X} 30 s",
  "Mark a 5 m square with four cones. No ball needed.",
  ["Start in the middle in your stance.", "Shuffle to one cone and back to the middle, then sprint to the next cone.",
   "Drop step and run back to the middle, then shuffle to the next.", "Keep moving round the square at full speed for the whole set."],
  ["Go from shuffle to sprint without standing up tall.", "Short steps when you change direction.", "Back in your stance in the middle every time."],
  ["DEF", "PHY"], ["Defending", "1v1s", "Speed"],
  board([cone(-2.5, -2.5), cone(2.5, -2.5), cone(-2.5, 2.5), cone(2.5, 2.5)], [you(0, 0)], [],
        [run((-0.3, 0), (-2.2, -2.2)), run((-2, -1.7), (-0.2, 0.2)), run((0.3, 0), (2.2, -2.2))]),
  ball=False, gear=["4 cones"], space="5 m square", progression="Make the square 7 m and hold the pace for 45 s.")

# ---- Awareness
D("eyes-up-dribble", "Eyes Up Dribble", "Awareness", 1, 4, f"3 {X} 45 s",
  "Mark a 10 m square with four cones. Pick something far away to look at, like a tree or a goalpost.",
  ["Dribble slowly around inside the square.", "Every three touches, lift your eyes and look at your far-away spot.",
   "Look back down only to find the ball, then up again.", "Change direction whenever you get near a side."],
  ["Feel the ball with your feet so your eyes are free.", "Small touches make looking up easier.", "Try to keep the ball at the bottom of your view while you look up."],
  ["DRI", "BC"], ["Vision", "Dribbling", "Composure"],
  board([cone(-5, -5), cone(5, -5), cone(-5, 5), cone(5, 5)], [you(-1, 1)], [[-0.7, 0.6]], [run((-1, 1), (2, -1), (0, -3), (-3, -1), (-2, 2))]),
  gear=["Ball", "4 cones"], space="10 m square", progression="Look up every two touches, then every touch.", tags=["warm-up"])
D("colour-cones", "Colour Corners", "Awareness", 2, 4, f"3 {X} 60 s",
  "Put four cones of different colours (red, blue, yellow and green) in a square about 6 big steps across. "
  "Stand in the middle with the ball. Prop your phone up nearby with the sound on.",
  ["Wait in the middle with the ball at your feet, on your toes.", "The phone calls a colour.",
   "Dribble round that cone and back to the middle as fast as you can.", "Get set again, ready for the next call."],
  ["Know where every colour is before the first call.", "Turn tight round the cone with small touches.", "Get back to the middle and get set: the next call is coming."],
  ["DRI", "BC"], ["Vision", "Dribbling", "Speed"],
  board([cone(-2.5, -2.5, "red"), cone(2.5, -2.5, "blue"), cone(-2.5, 2.5, "green"), cone(2.5, 2.5, "yellow")], [you(0, 0.3)], [[0, -0.1]],
        [run((0.2, -0.2), (2.2, -2.6), (2.9, -2.9), (2.7, -2.1), (0.4, 0.1))]),
  gear=["Ball", "4 coloured cones"], space="5 m square", progression="Faster calls, or two colours in a row before you come back.",
  tags=["quick feet"])
D("two-look-wall", "Two-Look Wall Passes", "Awareness", 2, 4, f"3 {X} 10 passes",
  "Stand 4 m from a wall, with a cone 3 m behind you to the left and another to the right.",
  ["Pass against the wall.", "While the ball travels, look over your left shoulder, then your right.",
   "Say what you saw out loud: \"left cone, right cone\".", "Control the rebound and pass again."],
  ["Both looks happen before the ball comes back.", "Turn your head, not your whole body.", "Look quickly: a glance, not a stare."],
  ["PAS", "BC"], ["Vision", "First touch", "Composure"],
  board(wall(-4) + [cone(-2.5, 3), cone(2.5, 3)], [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -3.8), both=True)]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 8 m",
  progression="Ask a friend to stand behind you holding up fingers, and shout the number.")
D("half-turn-receive", "Half-Turn Receive", "Awareness", 3, 5, f"3 {X} 10 passes",
  "Stand 4 m from a wall. Put a gate of two cones 6 m behind you.",
  ["Stand half-turned: one shoulder to the wall, one to the gate.", "Pass against the wall.",
   "Glance at the gate while the ball comes back.", "Receive on your back foot and play straight through the gate. Fetch the ball and go again."],
  ["Half-turned means you can see both ways.", "Glance before you receive, not after.", "Two touches: one to receive, one to pass."],
  ["PAS", "BC"], ["Vision", "First touch", "Passing"],
  board(wall(-4) + [cone(-1, 6), cone(1, 6)], [you(0, 0.4, PI * 0.75)], [[0, 0]],
        [ball((0, 0), (0, -3.8), both=True), ball((0.2, 0.3), (0, 6))]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 10 m", progression="Play through the gate with your first touch.")
D("juggle-and-look", "Juggle and Look", "Awareness", 3, 5, f"3 {X} 60 s",
  "Stand in open space. Pick three things around you to look at, like a tree, a goal and a fence.",
  ["Juggle the ball with your feet.", "After every touch, glance at one of your three things.",
   "Keep going round the three in order.", "If the ball drops, start the count again."],
  ["Touch, look, touch, look.", "Keep the juggles low so the ball comes back quickly.", "Feel the ball: you can't watch it all the time."],
  ["BC"], ["Vision", "Ball control", "Composure"], spot(),
  progression="Use your thighs as well, still looking between touches.", tags=["touch", "anywhere"])
D("find-the-gap", "Find the Gap", "Awareness", 3, 5, f"3 {X} 45 s",
  "Mark a 12 m square. Scatter eight cones inside it as defenders.",
  ["Dribble around inside the square.", "Look up and find the biggest space between the cones.",
   "Dribble into that space, then look for the next one.", "Never go closer than a big step to a cone."],
  ["Look first, then move.", "The space changes as you move: keep checking.", "Speed up into space, slow down near cones."],
  ["DRI", "BC"], ["Vision", "Dribbling", "Positioning"],
  board([cone(-6, -6), cone(6, -6), cone(-6, 6), cone(6, 6), cone(-3, -2), cone(2, -3), cone(0, 1), cone(-2, 3), cone(3, 2),
         cone(4, -1), cone(-4, 0), cone(1, 4.5)], [you(-4, 4.5)], [[-3.7, 4.1]],
        [run((-4, 4.5), (-1.5, 1.5), (1, -1), (-0.5, -4.5), (3, -4.5))]),
  gear=["Ball", "12 cones"], space="12 m square", progression="Put in two more cones and go faster.")
D("dribble-and-count", "Dribble and Count", "Awareness", 4, 5, f"3 {X} 60 s",
  "Put six cones in a line, one big step apart.",
  ["Dribble in and out of the cones.", "At the same time, count backwards from 100 in threes, out loud.",
   "Turn at the end and weave back without stopping the count.", "If you stop counting or miss a cone, start again from 100."],
  ["Your feet look after the ball while your head is busy.", "Keep the touches small and the rhythm steady.", "Head up: you can't read a game while staring at the ball."],
  ["DRI", "BC"], ["Vision", "Composure", "Dribbling"],
  board([cone(0, -z) for z in range(1, 7)], [you(0, 0.6)], [[0.2, 0.2]],
        [run((0, 0.6), (0.6, -1), (-0.6, -2), (0.6, -3), (-0.6, -4), (0.6, -5), (-0.6, -6), (0, -6.8))]),
  gear=["Ball", "6 cones"], space="8 m long", progression="Name an animal for each letter of the alphabet instead.")
D("look-then-play", "Look, Then Play", "Awareness", 5, 6, f"3 {X} 10 passes",
  "Stand 4 m from a wall. Put three small gates of two cones behind you, about 6 m away: left, middle and right.",
  ["Pass against the wall.", "While the ball comes back, check over your shoulder and pick a gate you didn't use last time.",
   "Turn on your first touch and pass through that gate with your second.", "Fetch the ball and go again, as quickly as you can."],
  ["Look before the ball arrives, every time.", "Two touches only: turn, then pass.", "Time the set and beat it next time."],
  ["PAS", "BC"], ["Vision", "First touch", "Passing"],
  board(wall(-4) + [cone(-4.5, 5.5), cone(-3.5, 6.5), cone(-0.6, 6.5), cone(0.6, 6.5), cone(3.5, 6.5), cone(4.5, 5.5)],
        [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -3.8), both=True), ball((0.3, 0.6), (4, 6.2))]),
  gear=["Ball", "Wall", "6 cones"], space="A wall and 10 m", progression="Ask a friend behind you to point at a gate, and use a different one.")

# ---- Goalkeeping
D("gk-hand-speed", "Hand Speed", "Goalkeeping", 1, 3, f"3 {X} 30 s",
  "Stand with your feet apart and the ball in your hands.",
  ["Pass the ball round your waist from hand to hand, ten times each way.", "Then make a figure of eight through and round your legs.",
   "Then hold the ball out in front and tap it quickly between your fingertips.", "Keep the ball moving the whole time."],
  ["Use your fingers, not your palms.", "Watch the ball at first, then try looking ahead.", "Fast, but don't drop it."],
  ["DEF", "BC"], ["Composure", "Ball control"], spot(),
  progression="Do it while doing small jumps on the spot.", tags=["warm-up", "anywhere"])
D("gk-scoop", "Scoop Pick-Up", "Goalkeeping", 1, 4, f"3 {X} 10 rolls",
  "Stand 4 m from a wall.",
  ["Roll the ball firmly against the wall.", "As it comes back, step into its path with your feet close together.",
   "Bend forward and scoop it up with both hands, palms to the ball, little fingers almost touching.", "Bring it up into your chest. Roll it again."],
  ["Get your body behind the ball so it can't go through you.", "Hands go down to the ball: don't wait for it to bounce up.", "Fingers point at the ground."],
  ["DEF", "BC"], ["Positioning", "Composure"],
  board(wall(-4), [you(0, 0.4)], [[0, 0]], [ball((0, 0), (0, -3.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 5 m", progression="Roll it off to the side so you have to shuffle across first.")
D("gk-high-catch", "High Catch", "Goalkeeping", 2, 5, f"3 {X} 10 catches",
  "Stand in open space with the ball in your hands.",
  ["Throw the ball high above your head.", "Watch it come down and take a step toward it.",
   "Jump off one foot, knee up, and catch it at the highest point you can reach.", "Land balanced and bring the ball into your chest."],
  ["Hands make a W shape behind the ball, thumbs nearly touching.", "Catch it in front of your head, where you can see it.", "Your lifted knee protects you in a crowd."],
  ["DEF", "PHY"], ["Positioning", "Composure"],
  board([], [you(0, 0.6)], [[0.4, -0.6]], [run((0, 0.6), (0.3, -0.2))]),
  space="4 m square", progression="Throw it a little in front or to the side, so you have to move first.")
D("gk-shuffle-catch", "Shuffle and Catch", "Goalkeeping", 2, 5, f"3 {X} 40 s",
  "Stand 3 m from a wall with a cone 2 m to each side of you.",
  ["Shuffle sideways to one cone.", "Set your feet and throw the ball against the wall at chest height.",
   "Catch the rebound with your hands behind the ball.", "Shuffle across to the other cone and do it again."],
  ["Feet set before every throw and catch.", "Small side steps: never cross your feet.", "Watch the ball into your hands."],
  ["DEF", "PHY"], ["Positioning", "Composure"],
  board(wall(-3, 3) + [cone(-2, 0.4), cone(2, 0.4)], [you(-1.6, 0.4)], [[-1.6, 0]],
        [run((-1.6, 0.9), (1.6, 0.9), both=True), ball((-1.6, 0), (-1.6, -2.8), both=True)]),
  gear=["Ball", "Wall", "2 cones"], space="A wall and 5 m", progression="Throw it lower so you catch it at shin height.")
D("gk-collapse-save", "Collapse Save", "Goalkeeping", 2, 5, f"3 {X} 6 each side",
  "Put the ball on soft ground a big step to your side. Stand in your set position.",
  ["Step toward the ball with the near foot.", "Let your legs fold sideways so you drop onto your side.",
   "Put your bottom hand behind the ball and the top hand on top as you land.", "Pull the ball into your chest. Get up and swap sides."],
  ["Fall sideways, not backwards.", "Land on the side of your body, never your elbow.", "Hands reach the ball first."],
  ["DEF", "PHY"], ["Positioning", "Composure"],
  board([cone(-2, -1), cone(2, -1)], [you(0, 0.2)], [[1.3, 0.2]], [run((0, 0.2), (1.1, 0.2))]),
  gear=["Ball", "2 cones"], space="Soft ground, 4 m wide", progression="Roll the ball to your side and collapse onto it while it moves.")
D("gk-punch-clear", "Punch Clear", "Goalkeeping", 3, 5, f"3 {X} 8 punches",
  "Stand in open space with the ball in your hands.",
  ["Throw the ball up and a little in front of you.", "Make two fists side by side, knuckles flat.",
   "As it drops, punch through the bottom half of the ball, up and away.", "Fetch it and go again. Then try one fist, to send it to the side."],
  ["Punch through the ball, don't just tap it.", "Height and distance: get it out of danger.", "Keep your eyes open and on the ball."],
  ["DEF", "PHY"], ["Positioning", "Strength"],
  board([], [you(0, 0.6)], [[0, -0.2]], [ball((0, -0.2), (0, -9))]),
  space="10 m", progression="Jump off one foot as you punch.")
D("gk-punt-zone", "Punt to a Zone", "Goalkeeping", 3, 5, f"3 {X} 8 kicks",
  "Mark a 10 m square with four cones, 30 m away.",
  ["Hold the ball out in front of you at waist height.", "Take two steps and drop it onto your kicking foot.",
   "Strike it with your laces, toes pointed.", "Try to land it in the zone. Fetch it and go again."],
  ["Drop the ball, don't throw it up.", "Lock your ankle and follow through high.", "Aim for height and distance together."],
  ["PAS", "DEF"], ["Long balls", "Passing"],
  board([cone(-5, -25), cone(5, -25), cone(-5, -35), cone(5, -35)], [you(0, 0.6)], [[0, 0]], [ball((0, 0), (0, -30))]),
  gear=["Ball", "4 cones"], space="Half a pitch", progression="Kick with your other foot, or move the zone further away.")
D("gk-turn-catch", "Turn and Catch", "Goalkeeping", 4, 5, f"3 {X} 10 catches",
  "Stand 3 m from a wall, facing away from it, with the ball in your hands.",
  ["Throw the ball back over your head so it hits the wall.", "Turn round quickly as soon as it leaves your hands.",
   "Find the ball and catch it before it bounces twice.", "Throw higher or lower each time, so you never quite know where it will come."],
  ["Turn fast and find the ball with your eyes first.", "Get set before the catch, even for a split second.", "Hands behind the ball."],
  ["DEF", "BC"], ["Positioning", "Composure"],
  board(wall(-3), [you(0, 0.4, 0)], [[0, 0]], [ball((0, 0), (0, -2.8), both=True)]),
  gear=["Ball", "Wall"], space="A wall and 5 m", progression="Stand closer to the wall so the ball comes back faster.")
D("gk-up-and-down", "Up and Down Saves", "Goalkeeping", 4, 5, f"3 {X} 6 saves",
  "On soft ground, put the ball 1.5 m to your left and a cone 1.5 m to your right.",
  ["Start in your set position between them.", "Dive low to the left and trap the ball.",
   "Leave it, get up fast, and dive to touch the cone on the right.", "Get up and set. Swap the ball and the cone over every set."],
  ["Back on your feet quickly: one knee, then up.", "Set your feet before each dive.", "Hands lead, body follows."],
  ["DEF", "PHY"], ["Positioning", "Stamina", "Composure"],
  board([cone(1.5, 0)], [you(0, 0)], [[-1.5, 0]], [run((-0.3, 0.3), (-1.2, 0.3)), run((0.3, -0.3), (1.2, -0.3))]),
  gear=["Ball", "1 cone"], space="Soft ground, 4 m wide", progression="Take a step forward before each dive.")
D("gk-power-step-dive", "Power Step Dive", "Goalkeeping", 5, 6, f"3 {X} 6 each side",
  "Mark a goal with two cones 7 m apart, on soft ground. Put the ball 1 m inside one post, 1 m in front of the line.",
  ["Start in the middle in your set position.", "Take one short sideways step toward the ball with the near foot.",
   "Push off that foot and dive across, hands first, to grab the ball.", "Land on your side, get up and reset. Swap sides."],
  ["The power step is short and to the side, never backwards.", "Dive forward of the line, toward the ball, not along it.", "Bottom hand behind the ball, top hand on top."],
  ["DEF", "PHY"], ["Positioning", "Speed", "Composure"],
  board([cone(-3.5, 0), cone(3.5, 0)], [you(0, -0.6)], [[2.5, -1.4]], [run((0, -0.6), (0.6, -0.7)), run((0.6, -0.9), (2.3, -1.4))]),
  gear=["Ball", "2 cones"], space="Soft ground, 8 m wide", progression="Ask a friend to roll the ball toward the post as you start.")

# ---- Runs (no ball)
D("recovery-jog", "Recovery Jog", "Runs", 1, 10, f"2 {X} 5 min", "Find a pitch or a park with room to jog.",
  ["Jog slowly round the pitch.", "Keep it easy enough to chat the whole way.",
   "Walk for a minute between the two sets.", "Shake your arms and legs loose as you walk."],
  ["Slow is the point: this helps your legs recover.", "Breathe through your nose if you can.", "Soft, short steps."],
  ["PHY"], ["Stamina"],
  board([cone(-6, 0), cone(6, 0), cone(-6, -12), cone(6, -12)], [you(-6.6, 0.6)], [],
        [run((-6.6, 0.6), (-6.6, -12.6), (6.6, -12.6), (6.6, 0.6), (-5.6, 0.6))]),
  ball=False, gear=[], space="A pitch or a park", tags=["cool-down"])
D("fast-starts", "Fast Starts", "Runs", 2, 5, f"3 {X} 4 sprints", "Put two cones 10 m apart.",
  ["Sprint to the far cone from a standing start.", "Walk back.",
   "Next, start from kneeling, then sitting, then lying on your front.", "Get up and go as fast as you can each time."],
  ["The first three steps are short and powerful.", "Lean forward and drive your arms.", "Full rest between sprints: quality, not tiredness."],
  ["PHY"], ["Speed"],
  board(lane(10, 3), [you(0, 0.6)], [], [run((0, 0.6), (0, -10))]),
  ball=False, gear=["2 cones"], space="15 m", progression="Face the wrong way and turn before you go.")
D("shuttle-runs", "Shuttle Runs", "Runs", 2, 5, f"3 {X} 2 runs", "Put four cones in a line at 0, 5, 10 and 15 m.",
  ["Sprint to the 5 m cone, touch the ground, and sprint back.", "Then to the 10 m cone and back.",
   "Then to the 15 m cone and back. That is one run.", "Rest a minute and go again."],
  ["Stay low as you turn and touch the ground.", "Plant your outside foot to stop and turn.", "Keep your pace on the last leg."],
  ["PHY"], ["Speed", "Stamina"],
  board([cone(0, 0), cone(0, -5), cone(0, -10), cone(0, -15)], [you(0.6, 0.6)], [], [run((0.6, 0.4), (0.6, -14.6), both=True)]),
  ball=False, gear=["4 cones"], space="18 m", progression="Do two runs back to back before you rest.")
D("curved-runs", "Curved Runs", "Runs", 3, 5, f"3 {X} 4 runs",
  "Put a start cone, a second cone 6 m ahead and 6 m to the side as a defender, and a third 20 m ahead beyond it.",
  ["Jog toward the defender cone.", "Bend your run round the outside of it.",
   "Sprint on to the far cone, looking back over your shoulder as if for a pass.", "Walk back and go round the other way."],
  ["Bend the run so you stay level with the defender until you go.", "Lean into the curve like a bike going round a corner.", "Look back for the ball without slowing down."],
  ["PHY"], ["Speed", "Positioning"],
  board([cone(0, 0), cone(6, -6), cone(8, -20)], [you(0, 0.6)], [], [run((0, 0.6), (3, -3.5), (5.5, -4.8), (7.2, -6), (8, -9), (8, -19.4))]),
  ball=False, gear=["3 cones"], space="25 m", progression="Make the sprint after the curve 30 m.")
D("speed-play", "Speed Play", "Runs", 3, 12, f"2 {X} 6 min", "Find a pitch or a park with room to run.",
  ["Jog easily for one minute.", "Run at a strong pace for 30 seconds.", "Sprint flat out for 10 seconds, then jog again.",
   "Keep mixing jog, strong and sprint until the six minutes are up. Walk two minutes between sets."],
  ["Change speed like you do in a real game.", "Recover while you jog: don't stop.", "Sprints are short and all-out."],
  ["PHY"], ["Stamina", "Speed"],
  board([cone(-6, 0), cone(6, 0), cone(-6, -12), cone(6, -12)], [you(-6.6, 0.6)], [],
        [run((-6.6, 0.6), (-6.6, -12.6)), run((-6.6, -12.6), (6.6, -12.6)), run((6.6, -12.6), (6.6, 0.6))]),
  ball=False, gear=[], space="A pitch or a park", progression="Make it three sets.")
D("hill-sprints", "Hill Sprints", "Runs", 4, 6, f"2 {X} 5 sprints",
  "Find a grassy slope about 20 m long. Put a cone at the bottom and one at the top.",
  ["Sprint up the hill.", "Drive your knees and pump your arms hard.", "Walk slowly back down.", "Rest a full two minutes between sets."],
  ["Lean into the hill from your ankles.", "Short, quick steps.", "Every sprint is all-out: stop the set if you slow down a lot."],
  ["PHY"], ["Speed", "Strength"],
  board([cone(0, 0), cone(0, -20)], [you(0.6, 0.6)], [], [run((0.6, 0.6), (0.6, -20))]),
  ball=False, gear=["2 cones"], space="A 20 m slope", progression="Find a steeper slope, or add a sixth sprint.")
D("pyramid-sprints", "Pyramid Sprints", "Runs", 4, 6, f"2 {X} 5 sprints", "Put cones at 10 m, 20 m and 30 m from a start cone.",
  ["Sprint 10 m and walk back.", "Sprint 20 m and walk back.", "Sprint 30 m and walk back.", "Then 20 m and 10 m again. That is one set."],
  ["Full speed every time, even on the short ones.", "Walk back slowly: that's your rest.", "Rest three minutes between sets."],
  ["PHY"], ["Speed", "Stamina"],
  board([cone(0, 0), cone(0, -10), cone(0, -20), cone(0, -30)], [you(0.6, 0.6)], [], [run((0.6, 0.6), (0.6, -30))]),
  ball=False, gear=["4 cones"], space="35 m")
D("box-to-box", "Box to Box", "Runs", 5, 8, f"2 {X} 6 runs", "Use a full pitch. The run is from one penalty box to the other, about 70 m.",
  ["Run from the edge of one box to the edge of the other in about 15 seconds.", "Jog back in about 45 seconds.",
   "That is one run. Do six without stopping.", "Rest three minutes, then do the second set."],
  ["Hit the time on every run, not just the first.", "Relaxed shoulders and hands, even at speed.", "Use the jog to get your breath back."],
  ["PHY"], ["Stamina", "Speed"],
  board([cone(-6, 0), cone(6, 0), cone(-6, -30), cone(6, -30)], [you(0, 0.6)], [], [run((0, 0.6), (0, -30)), run((1.5, -30), (1.5, 0.6))]),
  ball=False, gear=[], space="A full pitch", progression="Run it in 13 seconds.")

# ---- Core (no ball)
D("bird-dog", "Bird Dog", "Core", 1, 3, f"3 {X} 8 each side", "Kneel on all fours, hands under your shoulders and knees under your hips.",
  ["Reach one arm straight out in front.", "At the same time, push the opposite leg straight out behind you.",
   "Hold for two seconds, then bring them back in.", "Swap sides."],
  ["Keep your back flat like a table.", "Reach long, don't lift high.", "Move slowly and keep your hips level."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Touch elbow to knee under your body between reps.")
D("bridge-march", "Bridge March", "Core", 2, 3, f"3 {X} 10 each leg", "Lie on your back with knees bent and feet flat, hip width apart.",
  ["Lift your hips into a bridge.", "Keep them up and lift one foot a little off the ground.",
   "Put it down and lift the other.", "Keep marching slowly without letting your hips drop."],
  ["Hips stay level: don't let one side sag.", "Push through the heel of the foot on the ground.", "Squeeze your glutes the whole time."],
  ["PHY"], ["Strength", "Speed"], mat(), ball=False, gear=[], space="A mat", progression="Straighten the leg out as you lift it.")
D("seated-twists", "Seated Twists", "Core", 2, 3, f"3 {X} 20 twists", "Sit on the ground with knees bent and heels on the floor. Lean back a little.",
  ["Clasp your hands in front of your chest.", "Turn your shoulders and touch your hands to the ground beside your hip.",
   "Turn to the other side.", "Keep going without rushing."],
  ["Turn from your stomach, not just your arms.", "Keep your back straight, not rounded.", "Breathe out on every turn."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Lift your feet off the ground for the whole set.")
D("hollow-hold", "Hollow Hold", "Core", 3, 3, f"3 {X} 20 s", "Lie on your back with your arms by your sides.",
  ["Press your lower back into the ground.", "Lift your shoulders and your legs a little off the ground.",
   "Reach your arms toward your feet.", "Hold the shape and keep breathing."],
  ["Lower back stays glued to the floor.", "The lower your legs, the harder it is: start higher.", "Chin tucked, eyes on your toes."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Reach your arms above your head.")
D("bear-crawl", "Bear Crawl", "Core", 3, 4, f"3 {X} 10 m", "Mark out 10 m. Start on your hands and toes with your knees just off the ground.",
  ["Move your right hand and left foot forward together.", "Then your left hand and right foot.",
   "Crawl to the end, keeping your knees low.", "Crawl back the other way, going backwards."],
  ["Back flat: a cup of water on it shouldn't spill.", "Knees hover just off the ground.", "Small steps keep it controlled."],
  ["PHY"], ["Strength", "Stamina"],
  board(lane(10, 2), [you(0, 0.6)], [], [run((0, 0.6), (0, -10), both=True)]),
  ball=False, gear=["2 cones"], space="10 m", progression="Crawl sideways as well.")
D("v-sits", "V-Sits", "Core", 4, 3, f"3 {X} 10", "Lie on your back with your arms stretched above your head and your legs straight.",
  ["Lift your arms and legs at the same time.", "Reach your hands toward your toes so your body makes a V.",
   "Lower back down slowly.", "Don't let your feet touch the ground between reps."],
  ["Slow on the way down: that's where the work is.", "Keep your legs as straight as you can.", "Breathe out as you lift."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Hold the V at the top for two seconds.")
D("star-side-plank", "Star Side Plank", "Core", 5, 3, f"2 {X} 20 s each side", "Lie on your side with your feet stacked.",
  ["Push up onto your hand with your arm straight.", "Lift your hips so your body is straight.",
   "Lift your top arm and top leg so you make a star.", "Hold, then swap sides."],
  ["Hand right under your shoulder.", "Hips high: don't let them sag.", "Keep the top leg lower if you wobble."],
  ["PHY"], ["Strength"], mat(), ball=False, gear=[], space="A mat", progression="Lift the top leg up and down slowly while you hold.")

# ---- Stretching (no ball)
D("leg-swings", "Leg Swings", "Stretching", 1, 2, f"2 {X} 10 each leg", "Stand side-on to a wall or fence and rest one hand on it.",
  ["Swing your outside leg forward and back like a pendulum.", "Start small and let the swings get bigger.",
   "Then face the wall and swing the leg across your body and out to the side.", "Swap legs."],
  ["Stand tall on the standing leg.", "Relaxed swings, never forced.", "Keep your hips facing forward."],
  ["PHY"], ["Speed"],
  board(wall(-1, 1), [you(0, 0.2, PI / 2)], [], [run((-0.7, 0.7), (0.7, 0.7), both=True)]),
  ball=False, gear=[], space="A wall or fence", tags=["warm-up"])
D("lunge-and-twist", "Lunge and Twist", "Stretching", 1, 2, f"2 {X} 8 each side", "Find 10 m of space to walk.",
  ["Step forward into a long lunge.", "Turn your chest toward your front knee, arms out.",
   "Turn back to the middle, stand up and step through.", "Lunge with the other leg and twist the other way."],
  ["Front knee stays over your ankle.", "Back knee nearly touches the ground.", "Turn from your middle, slowly."],
  ["PHY"], ["Speed"],
  board(lane(8, 2), [you(0, 0.6)], [], [run((0, 0.6), (0, -8))]),
  ball=False, gear=[], space="10 m", tags=["warm-up"])
D("open-the-gate", "Open the Gate", "Stretching", 2, 2, f"2 {X} 10 each side", "Find 10 m of space to walk.",
  ["Lift one knee up in front of you.", "Swing it out to the side in a big circle, like opening a gate.",
   "Put it down and do the other leg.", "Walk back doing it the other way: from the side to the front, closing the gate."],
  ["Big, slow circles.", "Stand tall and keep your balance.", "Move from the hip, not the knee."],
  ["PHY"], ["Speed"],
  board(lane(8, 2), [you(0, 0.6)], [], [run((0, 0.6), (0, -8))]),
  ball=False, gear=[], space="10 m", tags=["warm-up"])
D("quad-stretch", "Standing Quad Stretch", "Stretching", 1, 2, f"2 {X} 30 s each side", "Stand next to a wall or fence for balance.",
  ["Hold the wall with one hand.", "Bend one knee and hold that foot behind you with your other hand.",
   "Pull the heel gently toward your bottom.", "Hold, then swap legs."],
  ["Knees side by side.", "Stand tall and push your hips forward a little.", "Gentle: a stretch, never pain."],
  ["PHY"], ["Speed"], board(wall(-1, 1), [you(0, 0.2, PI / 2)]), ball=False, gear=[], space="A wall or fence", tags=["cool-down"])
D("calf-stretch", "Calf Stretch", "Stretching", 1, 2, f"2 {X} 30 s each side", "Stand facing a wall, an arm's length away, with your hands on it.",
  ["Step one foot back, keeping that leg straight.", "Press the back heel into the ground.",
   "Lean toward the wall until you feel a stretch in your calf.", "Hold, then bend the back knee a little for a lower stretch. Swap legs."],
  ["Back toes point straight at the wall.", "Heel stays down.", "Breathe slowly."],
  ["PHY"], ["Speed"], board(wall(-1, 1), [you(0, 0.4)]), ball=False, gear=[], space="A wall", tags=["cool-down"])
D("butterfly-stretch", "Butterfly Stretch", "Stretching", 1, 2, f"2 {X} 30 s", "Sit on the ground with the soles of your feet together and your knees out to the sides.",
  ["Hold your feet with your hands.", "Sit up tall.", "Let your knees drop gently toward the ground.",
   "Hold. Lean forward a little from the hips to stretch further."],
  ["Don't bounce your knees.", "Keep your back long, not rounded.", "Relax and breathe out."],
  ["PHY"], ["Speed"], mat(), ball=False, gear=[], space="A mat", tags=["cool-down"])

# ---- Fitness: agility, footwork and jumps (no ball)
D("ladder-two-in", "Ladder Two Feet In", "Fitness", 1, 3, f"4 {X} 2 runs", "Lay an agility ladder on the ground, or chalk 8 boxes in a row.",
  ["Run through the ladder putting both feet in every box.", "Right foot, left foot, then on to the next box.",
   "Pump your arms and stay on the balls of your feet.", "Walk back and go again, a little faster."],
  ["Quick, light feet: don't stamp.", "Look ahead, not down at your feet.", "Go faster only once the pattern is clean."],
  ["PHY"], ["Speed"],
  board([ladder(-1.8, 0, 8)], [you(-2.6, 0, PI / 2)], [], [run((-2.2, 0), (2.4, 0))]),
  ball=False, gear=["Agility ladder"], space="6 m", progression="One foot in each box, as fast as you can.", tags=["warm-up", "quick feet"])
D("ladder-in-out", "Ladder In-Outs", "Fitness", 2, 3, f"4 {X} 2 runs",
  "Lay an agility ladder on the ground, or chalk 8 boxes in a row. Stand at one end, beside the ladder, facing across it.",
  ["Step into the first box with your right foot, then your left.", "Step back out with your right, then your left, one box further along.",
   "Keep going in, in, out, out all the way down.", "Come back the other way leading with your left foot."],
  ["Say the rhythm out loud: in, in, out, out.", "Stay low with your knees bent.", "Arms move with your feet."],
  ["PHY", "DEF"], ["Speed", "Defending"],
  board([ladder(-1.8, 0, 8)], [you(-1.6, 0.9)], [], [run(*[(-1.6 + 0.45 * i, 0 if i % 2 else 0.7) for i in range(9)])]),
  ball=False, gear=["Agility ladder"], space="6 m", progression="Do it twice as fast, then go backwards.", tags=["quick feet"])
D("squat-jumps", "Squat Jumps", "Fitness", 2, 3, f"3 {X} 8 jumps", "Stand on soft ground with your feet shoulder width apart.",
  ["Squat down until your thighs are nearly flat.", "Jump straight up as high as you can, swinging your arms up.",
   "Land softly with bent knees, straight back into the next squat.", "Rest a few seconds if your landings get loud."],
  ["Knees push out over your toes, never inward.", "Land quietly, like a cat.", "Chest up the whole time."],
  ["PHY"], ["Strength", "Speed"], mat(), ball=False, gear=[], space="Soft ground",
  progression="Pause for two seconds at the bottom before each jump.")
D("skater-bounds", "Skater Bounds", "Fitness", 3, 4, f"3 {X} 12 bounds", "Put two cones 2 m apart on soft ground.",
  ["Stand on one leg beside one cone.", "Jump sideways off that leg and land on the other leg by the other cone.",
   "Hold the landing for a second, like a speed skater.", "Bound back the other way. Keep going."],
  ["Push off hard from the side of your foot.", "Land softly on a bent knee, balanced.", "Swing your arms across your body."],
  ["PHY"], ["Speed", "Strength"],
  board([cone(-1, 0), cone(1, 0)], [you(-1, 0.7)], [], [run((-0.8, 0.7), (0, 0.2), (0.8, 0.7), both=True)]),
  ball=False, gear=["2 cones"], space="4 m wide", progression="Move the cones to 3 m apart.")
D("hurdle-hops", "Mini Hurdle Hops", "Fitness", 4, 4, f"4 {X} 2 runs",
  "Put five mini hurdles in a row, about 1 m apart. Rolled-up towels or shoes work too.",
  ["Stand in front of the first hurdle with your feet together.", "Hop over it with both feet and land softly.",
   "Bounce straight over the next one, and the next.", "Walk back and go again."],
  ["Quick off the ground: spend as little time on it as you can.", "Knees up, toes up.", "Land on the balls of your feet."],
  ["PHY"], ["Speed", "Strength"],
  board([hurdle(0, -z) for z in range(1, 6)], [you(0, 0.6)], [], [run((0, 0.6), (0, -5.8))]),
  ball=False, gear=["5 mini hurdles"], space="8 m", progression="Hop on one leg.")
D("star-run", "Star Run", "Fitness", 5, 5, f"4 {X} 1 round", "Put one cone in the middle and five cones in a circle around it, each 5 m away.",
  ["Start at the middle cone.", "Sprint out to the first outside cone and back to the middle.",
   "Then shuffle sideways out to the next cone and back.",
   "Keep going round all five, changing how you move each time: sprint, shuffle, run backwards."],
  ["Touch every cone, then turn fast.", "Stay low as you change direction.", "Head up: look at where you're going next."],
  ["PHY"], ["Speed", "Stamina"],
  board([cone(0, 0)] + [cone(round(5 * math.sin(a * 2 * PI / 5), 2), round(-5 * math.cos(a * 2 * PI / 5), 2)) for a in range(5)],
        [you(0, 0.6)], [], [run((0, -0.4), (0, -4.5), both=True), run((0.4, -0.1), (4.4, -1.4), both=True)]),
  ball=False, gear=["6 cones"], space="12 m square", progression="Make the circle 7 m wide.")

# ==== end of the second batch ====

# ---------------------------------------------------------------------------------------------------------------
# everything else the app's Library expects
# ---------------------------------------------------------------------------------------------------------------
CATEGORIES = ["Ball mastery", "Dribbling", "First touch", "Passing", "Shooting", "Defending", "Awareness",
              "Goalkeeping", "Fitness", "Runs", "Core", "Stretching"]
LEVEL_NAMES = ["Starter", "Park", "Club", "Academy", "Pro", "World Class"]   # indexed by a drill's level (1 to 5)
LEVELS = [
    {"id": "park", "name": "Park", "minutes": 15, "line": "Short and simple. Get the habit going."},
    {"id": "club", "name": "Club", "minutes": 20, "line": "A proper session a few times a week."},
    {"id": "academy", "name": "Academy", "minutes": 30, "line": "More drills and more sets."},
    {"id": "pro", "name": "Pro", "minutes": 40, "line": "Harder drills at match speed."},
    {"id": "world-class", "name": "World Class", "minutes": 50, "line": "Everything, at full intensity."},
]
POSITIONS = {"GK": "Goalkeeper", "CB": "Centre Back", "LB": "Left Back", "RB": "Right Back", "LWB": "Left Wing Back",
             "RWB": "Right Wing Back", "CDM": "Defensive Midfielder", "CM": "Central Midfielder",
             "CAM": "Attacking Midfielder", "LM": "Left Midfielder", "RM": "Right Midfielder", "LW": "Left Winger",
             "RW": "Right Winger", "ST": "Striker"}
AXES = [
    {"key": "shooting", "label": "Shooting", "builds": "Striking the ball cleanly and finishing chances."},
    {"key": "passing", "label": "Passing", "builds": "Finding a teammate short and long, with either foot."},
    {"key": "dribbling", "label": "Dribbling", "builds": "Keeping the ball close and beating a player."},
    {"key": "defending", "label": "Defending", "builds": "Staying in front of an attacker and winning the ball."},
    {"key": "physical", "label": "Physical", "builds": "Speed, stamina and strength."},
    {"key": "control", "label": "Ball control", "builds": "First touch and comfort on the ball."},
]

def session(id, title, kind, by_level):
    """A ready-made session: one drill list per training level (Park to World Class)."""
    return {"id": id, "title": title, "kind": kind, "levels": [[{"id": d, "sets": s} for d, s in lv] for lv in by_level]}

def grow(base, extra):
    """Five levels from one core list: each level adds a drill or a set."""
    out, cur = [], list(base)
    for i in range(5):
        if i and i - 1 < len(extra): cur = cur + [extra[i - 1]]
        out.append([(d, s + (1 if i >= 3 else 0)) for d, s in cur])
    return out

TECHNIQUE = [
    session("tech-ball-mastery", "Ball Mastery", None, grow(
        [("walking-knee-hug", 2), ("toe-taps", 3), ("foundations", 3), ("sole-rolls", 3)],
        [("inside-outside", 3), ("figure-8", 3), ("juggling", 3), ("hip-flexor-stretch", 2)])),
    session("tech-first-touch", "First Touch", None, grow(
        [("hamstring-sweep", 2), ("wall-passes", 3), ("wall-first-touch", 3)],
        [("scan-and-turn", 3), ("juggling", 3), ("weak-foot-laces", 3), ("hip-flexor-stretch", 2)])),
    session("tech-dribbling", "Dribbling", None, grow(
        [("walking-knee-hug", 2), ("foundations", 2), ("cone-slalom", 4), ("speed-dribble", 3)],
        [("figure-8", 3), ("stop-and-go", 3), ("inside-outside", 3), ("hamstring-sweep", 2)])),
    session("tech-finishing", "Finishing", None, grow(
        [("hamstring-sweep", 2), ("wall-passes", 3), ("laces-strike", 3)],
        [("touch-and-finish", 3), ("weak-foot-laces", 3), ("long-pass-target", 3), ("hip-flexor-stretch", 2)])),
]
WORKOUTS = [
    session("fx-speed", "Sprint Speed", "workout", grow(
        [("walking-knee-hug", 2), ("high-knee-runs", 3), ("strides", 4)],
        [("flying-20s", 4), ("glute-bridge", 3), ("repeat-sprints", 2), ("hamstring-sweep", 2)])),
    session("fx-core", "Core Strength", "workout", grow(
        [("dead-bug", 3), ("front-plank", 3), ("glute-bridge", 3)],
        [("side-plank", 2), ("plank-shoulder-taps", 3), ("mountain-climbers", 3), ("hip-flexor-stretch", 2)])),
    session("fx-engine", "Engine", "workout", grow(
        [("walking-knee-hug", 2), ("strides", 4), ("diagonals", 3)],
        [("mountain-climbers", 3), ("repeat-sprints", 2), ("high-knee-runs", 3), ("hamstring-sweep", 2)])),
]
HYBRID = [
    session("mix-sprint-shoot", "Sprint and Shoot", "hybrid", grow(
        [("walking-knee-hug", 2), ("strides", 3), ("laces-strike", 3)],
        [("flying-20s", 3), ("touch-and-finish", 3), ("speed-dribble", 3), ("hamstring-sweep", 2)])),
    session("mix-feet-core", "Quick Feet and Core", "hybrid", grow(
        [("toe-taps", 3), ("front-plank", 3), ("cone-slalom", 4)],
        [("dead-bug", 3), ("figure-8", 3), ("plank-shoulder-taps", 3), ("hip-flexor-stretch", 2)])),
]

def with_cool(levels, cool):
    """The same cool-down stretches at the end of every level (for a recovery session)."""
    return [lv + list(cool) for lv in levels]

# the second batch's sessions (2026-11): added after the first ones so the shelves keep their order
TECHNIQUE += [
    session("tech-passing-receiving", "Passing and Receiving", None, grow(
        [("hamstring-sweep", 2), ("wall-passes", 3), ("sole-trap", 3), ("short-gate-pass", 3)],
        [("back-foot-receive", 3), ("driven-pass", 3), ("wall-one-two", 3), ("quad-stretch", 2)])),
    session("tech-weak-foot", "Weak Foot", None, grow(
        [("leg-swings", 2), ("foundations", 3), ("left-right-wall", 3), ("weak-foot-receive", 3)],
        [("weak-foot-laces", 3), ("weak-foot-finish", 3), ("croqueta-rhythm", 3), ("calf-stretch", 2)])),
    session("tech-1v1-defending", "1v1 Defending", None, grow(
        [("open-the-gate", 2), ("defensive-stance", 3), ("jockey-shuffle", 3), ("poke-tackle", 3)],
        [("zigzag-jockey", 3), ("show-outside", 3), ("chase-down", 3), ("hip-flexor-stretch", 2)])),
    session("tech-goalkeeper", "Goalkeeper Basics", None, grow(
        [("leg-swings", 2), ("gk-hand-speed", 3), ("gk-set-and-catch", 3), ("gk-scoop", 3)],
        [("gk-high-catch", 3), ("gk-collapse-save", 3), ("gk-shuffle-catch", 3), ("butterfly-stretch", 2)])),
    session("tech-scanning", "Scanning and Awareness", None, grow(
        [("walking-knee-hug", 2), ("eyes-up-dribble", 3), ("two-look-wall", 3), ("colour-cones", 3)],
        [("scan-and-turn", 3), ("half-turn-receive", 3), ("find-the-gap", 3), ("hamstring-sweep", 2)])),
    session("tech-speed-dribbling", "Speed Dribbling", None, grow(
        [("lunge-and-twist", 2), ("box-dribble", 3), ("speed-dribble", 3), ("cut-and-go", 3)],
        [("stop-and-go", 3), ("slow-quick-lanes", 3), ("funnel-dribble", 3), ("quad-stretch", 2)])),
]
WORKOUTS += [
    session("fx-agility", "Agility", "workout", grow(
        [("leg-swings", 2), ("ladder-two-in", 4), ("ladder-in-out", 4), ("shuttle-runs", 3)],
        [("skater-bounds", 3), ("footwork-box", 3), ("star-run", 3), ("calf-stretch", 2)])),
    session("fx-mobility", "Mobility and Recovery", "workout", with_cool(grow(
        [("open-the-gate", 2), ("leg-swings", 2), ("recovery-jog", 1), ("bird-dog", 3)],
        [("bridge-march", 3), ("dead-bug", 3), ("seated-twists", 3), ("side-plank", 2)]),
        [("quad-stretch", 2), ("hip-flexor-stretch", 2), ("butterfly-stretch", 2)])),
    session("fx-leg-power", "Leg Power", "workout", grow(
        [("leg-swings", 2), ("squat-jumps", 3), ("glute-bridge", 3), ("fast-starts", 3)],
        [("skater-bounds", 3), ("hurdle-hops", 3), ("hill-sprints", 2), ("hip-flexor-stretch", 2)])),
]

def build():
    ladders = {}
    for d in sorted(DRILLS, key=lambda d: d["level"]):
        ladders.setdefault(d["skill"], []).append(d["id"])
    return {
        "categories": CATEGORIES, "levelNames": LEVEL_NAMES, "drills": DRILLS, "ladders": ladders, "removed": {},
        "moves": [{"id": "drag-back-turn", "name": "Drag-Back Turn", "level": 1,
                   "use": "Turn away from a defender who is closing you down from the front.",
                   "scene": "cruyff", "dur": 3.0, "keyTimes": [0.0, 0.8, 1.6, 2.4],
                   "steps": [{"text": "Put your sole on top of the ball.", "k": 0}, {"text": "Drag it back behind your standing leg.", "k": 1},
                             {"text": "Turn your hips to follow it.", "k": 2}, {"text": "Push away with the other foot.", "k": 3}]}],
        "moveLevels": {"1": "Starter"},
        "templates": [{"id": "three-day-start", "name": "3-Day Start", "sub": "Ball work on Monday, Wednesday and Friday.",
                       "days": ["Mon", "Wed", "Fri"], "tint": "brand", "perDay": 3,
                       "drills": ["toe-taps", "foundations", "cone-slalom", "wall-passes", "juggling", "speed-dribble"]}],
        "axes": AXES, "start": {a["key"]: 40 for a in AXES}, "now": {a["key"]: 45 for a in AXES},
        "player": {"name": "Alex", "level": 3, "xp": 240, "xpMax": 500, "streak": 4, "position": "CM", "foot": "Right"},
        "positions": POSITIONS, "skills": CATEGORIES, "levels": LEVELS,
        "pros": [], "technique": TECHNIQUE, "fitness": [], "workouts": WORKOUTS, "hybrid": HYBRID,
    }

# ---------------------------------------------------------------------------------------------------------------
# checks: everything the app's code relies on (see the notes at the top)
# ---------------------------------------------------------------------------------------------------------------
STARTER_IDS = ["juggling", "toe-taps", "cone-slalom", "foundations", "figure-8", "weak-foot-laces", "wall-passes",
               "speed-dribble", "walking-knee-hug", "strides", "flying-20s", "diagonals", "dead-bug", "front-plank",
               "side-plank", "glute-bridge", "high-knee-runs", "repeat-sprints", "mountain-climbers", "plank-shoulder-taps"]
NO_BALL_STARTERS = STARTER_IDS[8:]
STAT_CODES = {"SHO", "PAS", "DRI", "DEF", "PHY", "BC"}
REPS = re.compile(r"^(\d+)\s*×\s*(\d+)\s*(.*)$")

def check(lib):
    errs = []
    need = ["categories", "levelNames", "drills", "ladders", "removed", "moves", "moveLevels", "templates", "axes", "start",
            "now", "player", "positions", "skills", "levels", "pros", "technique", "fitness", "workouts", "hybrid"]
    errs += [f"missing top-level key {k}" for k in need if k not in lib]
    ids = [d["id"] for d in lib["drills"]]
    if not ids: errs.append("no drills")
    errs += [f"duplicate drill id {i}" for i in set(ids) if ids.count(i) > 1]
    errs += [f"starter drill missing: {i}" for i in STARTER_IDS if i not in ids]
    by = {d["id"]: d for d in lib["drills"]}
    for i in NO_BALL_STARTERS:
        if i in by and "Ball" in by[i]["needs"]: errs.append(f"{i} is in a fitness starter session but needs a ball")
    for d in lib["drills"]:
        w = d["id"]
        for k, t in (("id", str), ("name", str), ("skill", str), ("level", int), ("who", str), ("min", int), ("space", str),
                     ("gear", list), ("kit", list), ("needs", list), ("setup", str), ("how", list), ("reps", str),
                     ("points", list), ("stats", list), ("fixes", list)):
            if not isinstance(d.get(k), t): errs.append(f"{w}: {k} must be {t.__name__}")
        if d["skill"] not in CATEGORIES: errs.append(f"{w}: unknown skill {d['skill']}")
        if not 1 <= d["level"] < len(lib["levelNames"]): errs.append(f"{w}: level {d['level']} has no name")
        if d["min"] < 1: errs.append(f"{w}: min must be at least 1")
        if not REPS.match(d["reps"]): errs.append(f"{w}: reps '{d['reps']}' is not 'sets x reps'")
        if not 3 <= len(d["how"]) <= 5: errs.append(f"{w}: how needs 3 to 5 steps")
        if set(d["stats"]) - STAT_CODES: errs.append(f"{w}: unknown stat {set(d['stats']) - STAT_CODES}")
        if any(not g.get("label") for g in d["kit"]): errs.append(f"{w}: kit label missing")
        if ("Ball" in d["needs"]) != ("Ball" in d["gear"]): errs.append(f"{w}: gear and needs disagree about the ball")
        b = d.get("board")
        if b is None: errs.append(f"{w}: no board (the app would show an empty box)"); continue
        for k in ("props", "players", "balls", "paths"):
            if not isinstance(b.get(k), list): errs.append(f"{w}: board.{k} missing")
        if not b["players"] or b["players"][0]["kit"] != "you": errs.append(f"{w}: first board player must be you")
        for p in b["props"]:
            if not all(k in p for k in ("k", "x", "z", "yaw")): errs.append(f"{w}: prop needs k, x, z, yaw")
            if p.get("k") == "ladder" and p.get("rungs", 4) < 1: errs.append(f"{w}: ladder rungs must be 1 or more")
        for m in b["players"]:
            if not all(k in m for k in ("kit", "x", "z", "yaw")): errs.append(f"{w}: player needs kit, x, z, yaw")
        if any(len(x) < 2 for x in b["balls"]): errs.append(f"{w}: ball needs [x, z]")
        for p in b["paths"]:
            if len(p["pts"]) < 2 or any(len(q) < 2 for q in p["pts"]): errs.append(f"{w}: path needs 2+ points of [x, z]")
    for skill, lst in lib["ladders"].items():
        errs += [f"ladder {skill}: unknown drill {i}" for i in lst if i not in by]
    for key in ("pros", "technique", "fitness", "workouts", "hybrid"):
        for s in lib[key]:
            if len(s["levels"]) != len(lib["levels"]): errs.append(f"{s['id']}: needs {len(lib['levels'])} level lists")
            for n, lv in enumerate(s["levels"]):
                got = [x["id"] for x in lv]
                errs += [f"{s['id']} level {n}: unknown drill {i}" for i in got if i not in by]
                if len(set(got)) != len(got): errs.append(f"{s['id']} level {n}: a drill appears twice")
                if any(x["sets"] < 1 for x in lv): errs.append(f"{s['id']} level {n}: sets must be 1 or more")
            if key in ("fitness", "workouts"):
                errs += [f"{s['id']}: fitness session uses a ball drill {x['id']}" for lv in s["levels"] for x in lv
                         if x["id"] in by and "Ball" in by[x["id"]]["needs"]]
    sids = [s["id"] for key in ("pros", "technique", "fitness", "workouts", "hybrid") for s in lib[key]]
    errs += [f"duplicate session id {i}" for i in set(sids) if sids.count(i) > 1]
    for m in lib["moves"]:
        if m["dur"] <= 0 or any(not 0 <= s["k"] < len(m["keyTimes"]) for s in m["steps"]): errs.append(f"move {m['id']}: bad timing")
    if not lib["moves"]: errs.append("moves must have at least one entry")
    for t in lib["templates"]:
        if t["perDay"] > 0 and not t["drills"]: errs.append(f"template {t['id']}: no drills")
        errs += [f"template {t['id']}: unknown drill {i}" for i in t["drills"] if i not in by]
        errs += [f"template {t['id']}: bad day {x}" for x in t["days"] if x not in ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")]
    for a in lib["axes"]:
        for tbl in ("start", "now"):
            if not isinstance(lib[tbl].get(a["key"]), int): errs.append(f"{tbl} has no number for axis {a['key']}")
    if not lib["axes"]: errs.append("axes must have at least one entry")
    errs += [f"position {c} missing" for c in ("GK", "CB", "LB", "RB", "LWB", "RWB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST")
             if c not in lib["positions"]]
    if set(lib["player"]) != {"name", "level", "xp", "xpMax", "streak", "position", "foot"}: errs.append("player fields wrong")
    for lv in lib["levels"]:
        if set(lv) != {"id", "name", "minutes", "line"}: errs.append("training level fields wrong")
    # the film-lesson button needs one solo, ball-only drill in each of these groups
    for group in (["Goalkeeping"], ["Defending"], ["Passing", "Awareness"], ["Shooting", "Dribbling"]):
        if not any(d["skill"] in group and d["who"] == "Solo" and set(d["needs"]) <= {"Ball"} for d in lib["drills"]):
            errs.append(f"no solo drill for {group}")
    return errs

if __name__ == "__main__":
    lib = build()
    errs = check(lib)
    if errs:
        print("\n".join("PROBLEM: " + e for e in errs)); sys.exit(1)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SoccerMax", "Resources", "library.json")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(lib, f, ensure_ascii=False, indent=1)
        f.write("\n")
    skills = {}
    for d in lib["drills"]: skills[d["skill"]] = skills.get(d["skill"], 0) + 1
    print(f"wrote {os.path.normpath(out)}: {len(lib['drills'])} drills, "
          f"{sum(len(lib[k]) for k in ('technique', 'workouts', 'hybrid'))} ready-made sessions, all checks passed")
    print("  " + ", ".join(f"{k} {v}" for k, v in skills.items()))
