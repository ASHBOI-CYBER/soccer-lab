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
def cone(x, z): return {"k": "cone", "x": x, "z": z, "yaw": 0}
def goal(x=0, z=-8): return {"k": "goal", "x": x, "z": z, "yaw": 0}
def ladder(x, z, rungs=6): return {"k": "ladder", "x": x, "z": z, "yaw": 0, "rungs": rungs}
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
    """A wall drawn as a tight row of cones across the top."""
    return [cone(x * 0.5, z) for x in range(int(-half * 2), int(half * 2) + 1)]
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
