# Rebuilds the programmes workbook layout (tabs, drop-downs, help text), copying the
# programmes from an existing copy:
#   python3 scripts/build_programmes_workbook.py . "programmes/Kinetix Programmes.xlsx" old.xlsx
# Only needed when the layout changes; normally just edit the workbook.
import json, sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.comments import Comment
from openpyxl.utils import get_column_letter

repo = sys.argv[1]
out = sys.argv[2]
from openpyxl import load_workbook
import warnings
warnings.filterwarnings("ignore")
src = load_workbook(sys.argv[3]) if len(sys.argv) > 3 else None
exercises = json.load(open(f"{repo}/Packages/TrainingEngine/Sources/TrainingEngine/Resources/exercises.json"))["exercises"]

FONT = "Arial"
H = Font(name=FONT, bold=True, color="FFFFFF", size=10)
HFILL = PatternFill("solid", fgColor="1F2A28")
INPUT = PatternFill("solid", fgColor="FFF2CC")   # yellow-ish: fill in
CALC = PatternFill("solid", fgColor="E8EEEC")    # grey: worked out for you
BODY = Font(name=FONT, size=10)
BOLD = Font(name=FONT, size=10, bold=True)
TITLE = Font(name=FONT, size=16, bold=True)
SUB = Font(name=FONT, size=11, bold=True)
NOTE = Font(name=FONT, size=9, italic=True, color="555555")
WRAP = Alignment(wrap_text=True, vertical="top")
thin = Side(style="thin", color="D0D7D5")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)
ROWS = 400  # rows prepared for input on the long sheets

wb = Workbook()

def header(ws, cols, widths, row=1):
    for i, (name, width) in enumerate(zip(cols, widths), start=1):
        c = ws.cell(row=row, column=i, value=name)
        c.font, c.fill, c.alignment, c.border = H, HFILL, Alignment(wrap_text=True, vertical="center"), BOX
        ws.column_dimensions[get_column_letter(i)].width = width
    ws.row_dimensions[row].height = 32
    ws.freeze_panes = ws.cell(row=row + 1, column=1)

def prepare(ws, first_row, last_row, input_cols, calc_cols=()):
    for r in range(first_row, last_row + 1):
        for c in input_cols:
            cell = ws.cell(row=r, column=c)
            cell.fill, cell.font, cell.border, cell.alignment = INPUT, BODY, BOX, WRAP
        for c in calc_cols:
            cell = ws.cell(row=r, column=c)
            cell.fill, cell.font, cell.border = CALC, BODY, BOX

def put(ws, row, values, start_col=1):
    for i, v in enumerate(values):
        if v is not None:
            ws.cell(row=row, column=start_col + i, value=v)

def dropdown(ws, rng, source, prompt=None):
    dv = DataValidation(type="list", formula1=source, allow_blank=True, showErrorMessage=True,
                        errorTitle="Choose from the list", error="Pick one of the options in the drop-down.")
    if prompt:
        dv.promptTitle, dv.prompt, dv.showInputMessage = "Tip", prompt, True
    ws.add_data_validation(dv)
    dv.add(rng)

# ---------------------------------------------------------------- Lists
lists = wb.active
lists.title = "Lists"
PROGRAMMES = [("First 5K", "first5k"), ("Faster 10K", "faster10k"), ("Half marathon", "halfMarathon"), ("Marathon", "marathon"),
              ("Build strength", "buildStrength"), ("Build muscle", "buildMuscle"), ("Balanced hybrid", "balancedHybrid")]
SESSION_TYPES = ["Easy", "Recovery", "Long", "Tempo", "Intervals", "Progression", "Fartlek", "Hills", "Shakeout", "Race"]
PHASES = ["Base", "Build", "Peak", "Deload", "Taper", "Race week"]
ZONES = [("E", "Easy", "Conversational. Easy runs, long runs, warm-ups, cool-downs, jog recoveries.", "VDOT easy range", "3–4"),
         ("STEADY", "Steady", "Between easy and marathon pace: relaxed but purposeful. Steady finishes and progressions.", "Marathon pace + 10–20 s/km", "4–5"),
         ("M", "Marathon", "Marathon race pace.", "VDOT marathon pace", "5–6"),
         ("HM", "Half-Marathon", "Half Marathon Pace", "VDOT half marathon pace", "5–6"),
         ("T", "Threshold", "Comfortably hard; ~1 hour race effort. Tempo runs, cruise intervals.", "VDOT threshold pace", "6–7"),
         ("10K", "10K", "10K race pace. Longer reps and fartlek surges.", "Predicted 10K pace from race time", "7–8"),
         ("5K", "5K", "5K race pace.", "Predicted 5K pace from race time", "8–9"),
         ("I", "Interval", "3K–5K race effort. VO2max reps of 2–5 minutes.", "VDOT interval pace", "8–9"),
         ("R", "Repetition", "Mile race effort. Short fast reps with full recovery.", "VDOT repetition pace", "9")]
SPLITS = [("Full body ×1", "fullBody1", 1), ("Full body ×2", "fullBody2", 2), ("Full body ×3", "fullBody3", 3),
          ("Upper / Lower", "upperLower", 4), ("Push / Pull / Legs", "ppl", 3), ("Push / Pull / Legs ×2", "ppl6", 6),
          ("Upper / Lower / Full", "upperLowerFull", 3), ("PPL + Upper / Lower", "pplUpperLower", 5)]
PATTERNS = [("Any squat", "squat"), ("Any hinge (deadlift)", "hinge"), ("Any hinge accessory (RDL, bridge)", "hingeAccessory"),
            ("Any lunge / split squat", "lunge"), ("Any calf raise", "calf"), ("Any horizontal push (bench, press-up)", "horizontalPush"),
            ("Any vertical push (overhead press)", "verticalPush"), ("Any horizontal pull (row)", "horizontalPull"),
            ("Any vertical pull (pull-up, pulldown)", "verticalPull"), ("Any arms", "arms"), ("Any core", "core"),
            ("Any anti-rotation core", "antiRotation")]
EMPHASIS = ["Normal", "Heavy", "Light", "None"]
ROLES = ["Main", "Accessory"]
YESNO = ["Yes", "No"]

cols = [("Programmes", [p[0] for p in PROGRAMMES]), ("Session types", SESSION_TYPES), ("Phases", PHASES),
        ("Zones", [z[0] for z in ZONES]), ("Splits", [s[0] for s in SPLITS]), ("Roles", ROLES), ("Yes / No", YESNO),
        ("Strength emphasis", EMPHASIS),
        ("Exercises", [p[0] for p in PATTERNS] + sorted({e["name"] for e in exercises}))]
LIST_REF = {}
for i, (name, values) in enumerate(cols, start=1):
    letter = get_column_letter(i)
    lists.cell(row=1, column=i, value=name).font = BOLD
    lists.column_dimensions[letter].width = 34 if name == "Exercises" else 22
    for r, v in enumerate(values, start=2):
        lists.cell(row=r, column=i, value=v).font = BODY
    LIST_REF[name] = f"Lists!${letter}$2:${letter}${len(values) + 1}"
lists.sheet_state = "visible"

# ---------------------------------------------------------------- Start here
start = wb.create_sheet("Start here", 0)
start.column_dimensions["A"].width = 3
start.column_dimensions["B"].width = 26
start.column_dimensions["C"].width = 100
r = 1
start.cell(row=r, column=2, value="Kinetix programmes").font = TITLE; r += 2
intro = [
    "You write the programmes; the app scales them to each person. Write paces as zones (E, M, T, I, R) and running volume "
    "as a percentage of the runner's starting weekly volume. The app turns those into real paces (from their race time) and "
    "kilometres (from their 'current weekly volume' onboarding answer), places the sessions on their chosen days, and keeps "
    "balancing running and lifting as they train.",
    "When you've finished (or changed) something, send the file back and Claude converts it into the app's programme files, "
    "checks it, and shows sample plans for a few typical runners before anything goes to TestFlight."]
for t in intro:
    c = start.cell(row=r, column=2, value=t); c.font = BODY; c.alignment = WRAP
    start.merge_cells(start_row=r, start_column=2, end_row=r, end_column=3); start.row_dimensions[r].height = 58; r += 1
r += 1
start.cell(row=r, column=2, value="Colours").font = SUB; r += 1
for fill, label in [(INPUT, "Yellow cells: fill these in (drop-downs where there's a fixed list)."),
                    (CALC, "Grey cells: worked out for you (checks and examples). Don't type here."),
                    (HFILL, "Dark headers: column names. Hover a header for a note.")]:
    start.cell(row=r, column=2).fill = fill
    start.cell(row=r, column=3, value=label).font = BODY; r += 1
r += 1
start.cell(row=r, column=2, value="Tabs, in the order to fill them").font = SUB; r += 1
tabs = [("Programmes", "One row per onboarding goal: length, runs and lifts per week, long-run cap, what happens at the end."),
        ("Run weeks", "Every week of every programme: phase, volume (% of starting volume), long run, strength emphasis."),
        ("Run sessions", "Every run in every week: type, key or optional, distance (or 'auto') and the workout."),
        ("Pace zones", "What E / M / T / I / R mean. Change the descriptions or add an effort guide; paces come from race times."),
        ("Strength splits", "The splits offered in onboarding (full body, upper/lower, PPL…): days per week and who they suit."),
        ("Split days", "Each day of each split: exercises (a specific one or 'any squat' etc.), role, and optional sets/reps."),
        ("Strength by goal", "Sets, reps and rest for main and accessory lifts, per goal (used unless a split day overrides them)."),
        ("Rules", "Safety limits and defaults: max weekly increase, starting volumes, long-run share, deload size."),
        ("Lists", "The options behind the drop-downs. Add exercises here only if they're also added to the app.")]
for name, text in tabs:
    start.cell(row=r, column=2, value=name).font = BOLD
    c = start.cell(row=r, column=3, value=text); c.font = BODY; c.alignment = WRAP; r += 1
r += 1
start.cell(row=r, column=2, value="Writing a workout").font = SUB; r += 1
syntax = [
    ("Zones", "@ E, STEADY, M, HM, T, 10K, 5K, I, R  (see Pace zones). Add 'effort' (e.g. @ T effort) to show the pace as a guide only, with no off-pace warnings."),
    ("Reps", "6 x 800 m @ I, 90 s jog between     5 x 1 km @ I, 2 min jog between     2 x 8 min @ T, 2 min jog between"),
    ("Mixed reps", "8 x (1 min @ I / 1 min E)     4 x (3 min @ 10K / 2 min @ HM / 1 min @ 5K / 2 min E)"),
    ("Continuous", "15 min continuous @ T     25 min continuous @ T"),
    ("Hills", "8 x 60 s uphill @ hard effort, jog back down   (timed reps, no pace target)"),
    ("Progressions", "4 km E → 3 km STEADY → 1 km HM   (the km set the shape; the app sizes the run)"),
    ("Finishes", "13 km E, final 3 km @ STEADY   (= last 3/13 of the run at STEADY)"),
    ("Strides", "4 km E + 4 x 20 s strides"),
    ("Plain runs", "E continuous run, Very relaxed recovery run, Long run conversational throughout: any wording without a zone is easy."),
    ("Race", "Session type Race: the race distance, at goal pace."),
    ("Warm-ups", "Rep and tempo sessions get an easy warm-up and cool-down added automatically (at least 1.5 km each)."),
    ("Distances", "Write km for a mid-level runner (~30 km/week). They set the shape; Distance 'auto' sizes each run from the runner's volume."),
]
for name, text in syntax:
    start.cell(row=r, column=2, value=name).font = BOLD
    c = start.cell(row=r, column=3, value=text); c.font = BODY; c.alignment = WRAP; r += 1
r += 1
start.cell(row=r, column=2, value="How volume is scaled").font = SUB; r += 1
scaling = [
    "100% in Run weeks = the programme's race-ready volume for the runner's level (Programmes tab).",
    "Where they start: their answer to 'How far do you run in a typical week?' (pre-filled from their last 4 weeks of runs when the app has them), "
    "kept between the minimum and maximum in Rules. Below race-ready, they build up to it (within the max weekly increase); "
    "above it, they ease down to it (Rules: ease down per week). Your weekly % shape, deloads and taper are kept either way.",
    "Raced in the last two weeks? Onboarding asks, and if they want it they get an easy first week before week 1. Nothing else adds that week.",
    "'auto' easy runs share whatever volume is left in the week after the long run and the workouts, evenly.",
    "Safety: a week is never more than Rules → 'Max weekly increase' above what the runner actually did the week before, "
    "and no single run exceeds Rules → 'Longest run' for their level (or the programme's long-run cap).",
    "Fewer run days than the programme has sessions? The app drops easy and recovery runs first. More days? It adds easy runs.",
    "Rep sessions keep their rep lengths; lower-volume runners get fewer reps so hard running stays a sensible share of their week (Rules: fast, threshold and steady reps max).",
    "Rep and tempo sessions get an easy warm-up and cool-down (Rules: warm-up). Other runs share what's left: easy 1, recovery 0.75, shakeout 0.6, progression 1.15, within the Rules' run-length limits.",
    "A race date lines the programme up so its last week is race week (early weeks skipped if it's sooner, base weeks repeated first if it's further away). The race is its full distance and isn't counted in the week's %.",
    "The worked example columns (grey) show what each week would be for a runner at the volume in Rules → 'Example runner'.",
]
for t in scaling:
    c = start.cell(row=r, column=2, value="•"); c.font = BODY
    c = start.cell(row=r, column=3, value=t); c.font = BODY; c.alignment = WRAP
    start.row_dimensions[r].height = 30; r += 1
for row in start.iter_rows():
    for cell in row:
        if cell.font is None or cell.font.name != FONT:
            cell.font = Font(name=FONT, size=cell.font.size if cell.font else 10)

# ---------------------------------------------------------------- Rules
rules = wb.create_sheet("Rules")
header(rules, ["Rule", "Beginner", "Intermediate", "Advanced", "Notes"], [44, 14, 14, 14, 70])
rule_rows = [
    ("Starting volume if they don't run yet (km/week)", 8, 15, 25, "Used when the runner answers 0 or doesn't know."),
    ("Minimum starting volume (km/week)", 8, 15, 25, "Their answer is raised to at least this."),
    ("Maximum starting volume (km/week)", 30, 60, 100, "Their answer is capped at this."),
    ("Longest single run (km)", 10, 21, 32, "No run is longer than this (the programme's long-run cap can be lower)."),
    ("Shortest run (km)", 3, 3, 4, "Runs shorter than this are dropped or merged."),
    ("Max weekly increase (fraction)", 0.10, 0.10, 0.12, "0.10 = 10%. Applies to what they actually ran, not just the plan."),
    ("Long run share when 'auto' (fraction of week)", 0.30, 0.30, 0.32, "Used when Run weeks → Long run is 'auto'."),
    ("Example runner (km/week)", 15, 30, 50, "Only for the grey example columns in Run weeks."),
    ("Warm-up and cool-down, each (fraction of week)", 0.06, 0.06, 0.06, "Added to rep and tempo sessions. Kept between the min and max below."),
    ("Warm-up minimum (km)", 1.5, 1.5, 1.5, "Also used when the long run and sessions already fill the week."),
    ("Warm-up maximum (km)", 2.5, 2.5, 2.5, ""),
    ("Fast reps max (fraction of week): I, R, 5K, hills", 0.10, 0.10, 0.10, "Hard running per session. Lower-volume runners get fewer reps; rep lengths never change."),
    ("Fast reps floor (km)", 2, 2, 2, "Always allowed at least this much, whatever the week's volume."),
    ("Threshold reps max (fraction of week): T, 10K", 0.15, 0.15, 0.15, ""),
    ("Threshold reps floor (km)", 3, 3, 3, ""),
    ("Steady reps max (fraction of week): STEADY, M, HM", 0.25, 0.25, 0.25, ""),
    ("Steady reps floor (km)", 4, 4, 4, ""),
    ("Recovery run max (fraction of long run)", 0.60, 0.60, 0.60, "Spare volume beyond these lengths adds an easy run if there's a free day."),
    ("Easy run max (fraction of long run)", 0.85, 0.85, 0.85, ""),
    ("Shakeout max (fraction of week)", 0.15, 0.15, 0.15, ""),
    ("Recovery week after the programme (fraction of starting)", 0.60, 0.60, 0.60, "Easy running only, then the programme repeats from their recent running."),
    ("Ease down per week when above race-ready (fraction)", 0.15, 0.15, 0.15, "Runners doing more than the race needs come down to its race-ready volume this much a week."),
    ("Easy first week after a race (fraction of current)", 0.60, 0.60, 0.60, "Only if they say in onboarding they've raced in the last two weeks and want an easy week."),
]
# Keep the owner's values when rebuilding from an existing copy.
if src and "Rules" in src.sheetnames:
    saved = {r[0]: r[1:4] for r in src["Rules"].iter_rows(min_row=2, values_only=True) if r and r[0]}
    rule_rows = [(r[0], *(saved[r[0]] if r[0] in saved and None not in saved[r[0]] else r[1:4]), r[4]) for r in rule_rows]
for i, row in enumerate(rule_rows, start=2):
    put(rules, i, row)
    rules.cell(row=i, column=1).font = BOLD
    rules.cell(row=i, column=5).font = NOTE
    for c in (2, 3, 4):
        cell = rules.cell(row=i, column=c)
        cell.fill, cell.font, cell.border = INPUT, Font(name=FONT, size=10, color="0000FF"), BOX
        if "fraction" in row[0]:
            cell.number_format = "0%"
rules.cell(row=len(rule_rows) + 3, column=1, value="Current app defaults are filled in; change any yellow value.").font = NOTE

# ---------------------------------------------------------------- Programmes
prog = wb.create_sheet("Programmes")
pcols = ["Programme", "Name shown in app", "Length (weeks)", "After the last week", "Runs per week (min)", "Runs per week (max)",
         "Lifts per week (min)", "Lifts per week (max)", "Long-run cap (km)", "Weekly volume cap (km)",
         "Race-ready volume: beginner (km/week)", "Race-ready volume: intermediate (km/week)", "Race-ready volume: advanced (km/week)",
         "Taper weeks", "Default split", "Description shown in onboarding", "Weeks written", "Sessions written"]
header(prog, pcols, [18, 22, 10, 18, 10, 10, 10, 10, 10, 10, 12, 12, 12, 9, 20, 60, 10, 10])
prog.cell(row=1, column=11).comment = Comment("The weekly volume this race needs at each level. Run weeks' % are a % of this. "
                                              "Runners below it build up to it; runners above it ease down to it.", "Kinetix")
READY = {"first5k": (20, 30, 45), "faster10k": (25, 40, 55), "halfMarathon": (30, 45, 65), "marathon": (40, 60, 85),
         "buildStrength": (10, 15, 25), "buildMuscle": (10, 15, 25), "balancedHybrid": (15, 25, 40)}
defaults = {
    "first5k": (8, "Repeat", 3, 4, 1, 2, 8, 25, 1, "Full body ×2", "Build up to running 5K comfortably, then race it."),
    "faster10k": (10, "Repeat", 3, 5, 1, 2, 16, 45, 1, "Full body ×2", "Sharper speed and threshold work to lower your 10K time."),
    "halfMarathon": (12, "Repeat", 3, 5, 1, 2, 22, 70, 2, "Full body ×2", "Aerobic base, threshold and a long run that builds to race distance."),
    "marathon": (16, "Repeat", 4, 6, 1, 2, 32, 100, 3, "Full body ×2", "Volume, long runs and marathon-pace work, with a three-week taper."),
    "buildStrength": (8, "Repeat", 1, 3, 2, 4, 10, 25, 1, "Upper / Lower", "Heavy compound lifts with enough running to keep your engine."),
    "buildMuscle": (8, "Repeat", 1, 3, 3, 5, 10, 25, 1, "Push / Pull / Legs", "Hypertrophy-focused lifting with easy aerobic running."),
    "balancedHybrid": (8, "Repeat", 2, 4, 2, 3, 16, 35, 1, "Full body ×3", "Run and lift in balance: get faster and stronger together."),
}
for i, (display, code) in enumerate(PROGRAMMES, start=2):
    length, after, rmin, rmax, lmin, lmax, cap, wcap, taper, split, desc = defaults[code]
    values = [display, display, length, after, rmin, rmax, lmin, lmax, cap, wcap, *READY[code], taper, split, desc]
    if src:
        # Copy the owner's values by column name, so added columns keep their defaults.
        sheader = [c.value for c in src["Programmes"][1]]
        srow = [c.value for c in src["Programmes"][i]]
        saved = dict(zip(sheader, srow))
        values = [saved[name] if name in saved and saved[name] is not None and name not in ("Weeks written", "Sessions written") else v
                  for name, v in zip(pcols, values)]
    put(prog, i, values)
    prog.cell(row=i, column=17, value=f"=COUNTIF('Run weeks'!$A$2:$A${ROWS + 1},A{i})")
    prog.cell(row=i, column=18, value=f"=COUNTIF('Run sessions'!$A$2:$A${ROWS + 1},A{i})")
prepare(prog, 2, 8, input_cols=range(2, 17), calc_cols=(17, 18))
for i in range(2, 9):
    prog.cell(row=i, column=1).font = BOLD
dropdown(prog, "D2:D8", '"Repeat,Repeat harder,Maintenance,Stop"', "What happens when the last week is done.")
dropdown(prog, "O2:O8", LIST_REF["Splits"], "The split suggested in onboarding (the user can change it).")
prog.cell(row=10, column=1, value="Programme names in column A are fixed (they match the onboarding goals). Values shown are the app's current defaults.").font = NOTE

# ---------------------------------------------------------------- Run weeks
weeks = wb.create_sheet("Run weeks")
wcols = ["Programme", "Week", "Phase", "Volume (% of race-ready)", "Long run", "Strength emphasis", "Notes for the runner",
         "Sessions written", "Example: week km", "Example: long run km"]
header(weeks, wcols, [18, 7, 12, 12, 12, 12, 50, 10, 11, 11])
weeks.cell(row=1, column=4).comment = Comment("100% = the programme's race-ready volume for the runner's level "
                                               "(Programmes tab), reached gradually from where they are now. 1.2 = 120%.", "Kinetix")
weeks.cell(row=1, column=5).comment = Comment("'auto' (Rules share of the week), a % of the week (e.g. 30%), or km (e.g. 14km).", "Kinetix")
weeks.cell(row=1, column=9).comment = Comment("An intermediate runner already at race-ready volume (Programmes tab).", "Kinetix")
prepare(weeks, 2, ROWS + 1, input_cols=range(1, 8), calc_cols=range(8, 11))
week_rows = [r[:7] for r in src["Run weeks"].iter_rows(min_row=2, values_only=True) if r[0]] if src else []
for i, row in enumerate(week_rows, start=2):
    put(weeks, i, list(row))
for i in range(2, ROWS + 2):
    weeks.cell(row=i, column=4).number_format = "0%"
    weeks.cell(row=i, column=8, value=f'=IF(A{i}="","",COUNTIFS(\'Run sessions\'!$A$2:$A${ROWS + 1},A{i},\'Run sessions\'!$B$2:$B${ROWS + 1},B{i}))')
    weeks.cell(row=i, column=9, value=f'=IF(OR(A{i}="",D{i}=""),"",ROUND(D{i}*INDEX(Programmes!$L$2:$L$8,MATCH(A{i},Programmes!$A$2:$A$8,0)),1))')
    weeks.cell(row=i, column=10, value=(f'=IF(I{i}="","",IF(LOWER(E{i})="auto",ROUND(I{i}*Rules!$C$8,1),'
                                       f'IF(RIGHT(E{i},1)="%",ROUND(I{i}*VALUE(LEFT(E{i},LEN(E{i})-1))/100,1),'
                                       f'IF(RIGHT(LOWER(E{i}),2)="km",VALUE(LEFT(E{i},LEN(E{i})-2)),IF(LOWER(E{i})="race","race",E{i})))))'))
dropdown(weeks, f"A2:A{ROWS + 1}", LIST_REF["Programmes"])
dropdown(weeks, f"C2:C{ROWS + 1}", LIST_REF["Phases"])
dropdown(weeks, f"F2:F{ROWS + 1}", LIST_REF["Strength emphasis"], "How hard the lifting is this week: Heavy, Normal, Light (deload) or None.")

# ---------------------------------------------------------------- Run sessions
sess = wb.create_sheet("Run sessions")
scols = ["Programme", "Week", "Order in week", "Session type", "Distance", "Workout", "Notes for the runner"]
header(sess, scols, [18, 7, 8, 13, 11, 60, 46])
sess.cell(row=1, column=3).comment = Comment("1, 2, 3… The app keeps this order when it places runs on the user's days, with hard sessions spread out.", "Kinetix")
sess.cell(row=1, column=5).comment = Comment("'auto' (sized from the week's volume), a % of the week (25%), or km (8km).", "Kinetix")
sess.cell(row=1, column=6).comment = Comment("See 'Writing a workout' on Start here. Blank for plain easy/long runs.", "Kinetix")
prepare(sess, 2, ROWS + 1, input_cols=range(1, 8))
TYPE_NAMES = {"e": "Easy", "easy": "Easy"}
session_rows = []
if src:
    header_row = [c.value for c in src["Run sessions"][1]]
    has_key = "Key session?" in header_row
    for r in src["Run sessions"].iter_rows(min_row=2, values_only=True):
        if not r[0]:
            continue
        r = list(r[:8]) if has_key else list(r[:7])
        if has_key:
            del r[4]
        r[3] = TYPE_NAMES.get(str(r[3]).strip().lower(), r[3])
        session_rows.append(r)
for i, row in enumerate(session_rows, start=2):
    put(sess, i, row)
dropdown(sess, f"A2:A{ROWS + 1}", LIST_REF["Programmes"])
dropdown(sess, f"D2:D{ROWS + 1}", LIST_REF["Session types"])

# ---------------------------------------------------------------- Pace zones
pz = wb.create_sheet("Pace zones")
header(pz, ["Code", "Name", "What it's for", "How the app sets it", "Effort (RPE /10)", "Your notes / changes"], [7, 14, 60, 22, 12, 50])
for i, z in enumerate(ZONES, start=2):
    put(pz, i, list(z))
prepare(pz, 2, len(ZONES) + 1, input_cols=(3, 5, 6))
pz.cell(row=len(ZONES) + 3, column=1, value="Paces come from the runner's recent race time (Jack Daniels' VDOT tables) and update as they get fitter. Codes can't be renamed; descriptions can.").font = NOTE

# ---------------------------------------------------------------- Strength splits
sp = wb.create_sheet("Strength splits")
header(sp, ["Split", "Days per week", "Day names (in order)", "Who it suits", "Shown in onboarding?", "Days written"], [22, 10, 40, 50, 12, 10])
split_days = {
    "fullBody1": "Full body A", "fullBody2": "Full body A, Full body B", "fullBody3": "Full body A, Full body B, Full body C",
    "upperLower": "Upper A, Lower A, Upper B, Lower B", "ppl": "Push, Pull, Legs", "ppl6": "Push A, Pull A, Legs A, Push B, Pull B, Legs B",
    "upperLowerFull": "Upper, Lower, Full body", "pplUpperLower": "Push, Pull, Legs, Upper, Lower"}
suits = {
    "fullBody1": "Very busy weeks or running-focused plans.", "fullBody2": "Most runners: two sessions that cover everything.",
    "fullBody3": "Balanced hybrid, newer lifters.", "upperLower": "Strength focus with 4 lifting days.",
    "ppl": "Muscle focus with 3 lifting days.", "ppl6": "Experienced lifters, muscle focus, light running.",
    "upperLowerFull": "3 days, a bit more volume per muscle than full body.", "pplUpperLower": "5 lifting days, muscle focus."}
for i, (display, code, days) in enumerate(SPLITS, start=2):
    put(sp, i, [display, days, split_days[code], suits[code], "Yes"])
    sp.cell(row=i, column=6, value=f"=SUMPRODUCT(('Split days'!$A$2:$A${ROWS + 1}=A{i})/COUNTIFS('Split days'!$A$2:$A${ROWS + 1},'Split days'!$A$2:$A${ROWS + 1}&\"\",'Split days'!$B$2:$B${ROWS + 1},'Split days'!$B$2:$B${ROWS + 1}&\"\"))")
prepare(sp, 2, len(SPLITS) + 1, input_cols=range(2, 6), calc_cols=(6,))
dropdown(sp, f"E2:E{len(SPLITS) + 1}", LIST_REF["Yes / No"])
for i in range(2, len(SPLITS) + 2):
    sp.cell(row=i, column=1).font = BOLD

# ---------------------------------------------------------------- Split days
sd = wb.create_sheet("Split days")
header(sd, ["Split", "Day name", "Order", "Exercise", "Role", "Sets", "Reps (low)", "Reps (high)", "Rest (s)", "Notes"],
       [22, 16, 7, 40, 11, 7, 9, 9, 9, 40])
sd.cell(row=1, column=4).comment = Comment("'Any squat' etc. lets the app pick for the user's equipment. A named exercise is used as written (or the closest swap if they can't do it).", "Kinetix")
sd.cell(row=1, column=6).comment = Comment("Leave Sets/Reps/Rest blank to use 'Strength by goal' for the Role.", "Kinetix")
prepare(sd, 2, ROWS + 1, input_cols=range(1, 11))
current = {  # today's app sessions, so the common splits start filled in
    "Full body ×2": [("Full body A", [("Any squat", "Main"), ("Any horizontal push (bench, press-up)", "Main"), ("Any horizontal pull (row)", "Accessory"), ("Any calf raise", "Accessory"), ("Any core", "Accessory")]),
                     ("Full body B", [("Any hinge (deadlift)", "Main"), ("Any vertical push (overhead press)", "Main"), ("Any vertical pull (pull-up, pulldown)", "Accessory"), ("Any lunge / split squat", "Accessory"), ("Any anti-rotation core", "Accessory")])],
    "Upper / Lower": [("Upper A", [("Any horizontal push (bench, press-up)", "Main"), ("Any horizontal pull (row)", "Main"), ("Any vertical push (overhead press)", "Accessory"), ("Any vertical pull (pull-up, pulldown)", "Accessory"), ("Any arms", "Accessory")]),
                      ("Lower A", [("Any squat", "Main"), ("Any hinge accessory (RDL, bridge)", "Accessory"), ("Any lunge / split squat", "Accessory"), ("Any calf raise", "Accessory"), ("Any core", "Accessory")]),
                      ("Upper B", [("Any vertical push (overhead press)", "Main"), ("Any vertical pull (pull-up, pulldown)", "Main"), ("Any horizontal push (bench, press-up)", "Accessory"), ("Any horizontal pull (row)", "Accessory"), ("Any core", "Accessory")]),
                      ("Lower B", [("Any hinge (deadlift)", "Main"), ("Any lunge / split squat", "Main"), ("Any calf raise", "Accessory"), ("Any anti-rotation core", "Accessory")])],
    "Push / Pull / Legs": [("Push", [("Barbell Bench Press", "Main", 4, 5, 8, 150), ("Overhead Press", "Main"), ("Incline Dumbbell Press", "Accessory"), ("Dumbbell Lateral Raise", "Accessory"), ("Triceps Pushdown", "Accessory")])],
}
r = 2
for split, days in current.items():
    for day, items in days:
        for order, item in enumerate(items, start=1):
            ex, role = item[0], item[1]
            extra = list(item[2:]) if len(item) > 2 else [None, None, None, None]
            put(sd, r, [split, day, order, ex, role] + extra)
            r += 1
sd.cell(row=r + 1, column=1, value="Full body ×2 and Upper / Lower are today's app sessions; Push is a started example with its own sets/reps. Add the rest of the splits below.").font = NOTE
dropdown(sd, f"A2:A{ROWS + 1}", LIST_REF["Splits"])
dropdown(sd, f"D2:D{ROWS + 1}", LIST_REF["Exercises"], "Pick 'Any …' to let the app choose for the user's equipment, or a named exercise.")
dropdown(sd, f"E2:E{ROWS + 1}", LIST_REF["Roles"])

# ---------------------------------------------------------------- Strength by goal
sg = wb.create_sheet("Strength by goal")
header(sg, ["Programme", "Role", "Sets", "Reps (low)", "Reps (high)", "Rest (s)", "Notes"], [18, 11, 7, 9, 9, 9, 50])
presc = {"buildStrength": [(5, 4, 6, 180), (3, 8, 10, 90)], "buildMuscle": [(4, 8, 12, 120), (3, 10, 15, 75)],
         "balancedHybrid": [(4, 6, 8, 150), (3, 8, 12, 75)], "running": [(3, 5, 8, 150), (2, 8, 12, 60)]}
r = 2
for display, code in PROGRAMMES:
    key = code if code in presc else "running"
    for role, values in zip(ROLES, presc[key]):
        put(sg, r, [display, role] + list(values)); r += 1
prepare(sg, 2, r - 1, input_cols=range(3, 8))
sg.cell(row=r + 1, column=1, value="Current app defaults. Running goals share the 'running' prescription today; set each one as you like.").font = NOTE
sg.cell(row=r + 2, column=1, value="Weights progress automatically (double progression): add reps up to the top of the range, then add weight.").font = NOTE

# Fonts everywhere default to Arial
for ws in wb.worksheets:
    for row in ws.iter_rows():
        for cell in row:
            if cell.value is not None and (cell.font is None or cell.font.name != FONT):
                f = cell.font
                cell.font = Font(name=FONT, size=f.size or 10, bold=f.bold, italic=f.italic, color=f.color)
    ws.sheet_view.zoomScale = 110

order = ["Start here", "Programmes", "Run weeks", "Run sessions", "Pace zones", "Strength splits", "Split days", "Strength by goal", "Rules", "Lists"]
wb._sheets = [wb[n] for n in order]
wb.active = 0
wb.save(out)
print("saved", out)
